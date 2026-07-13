"""
http_app.py: the VICTIM PLANE, plain HTTP on port 80 (file 09 F3).

Phase 1 sent victims from this portal to the self-signed HTTPS app, which
meant certificate warnings on a captive portal: security theater with a
real usability cost, since the cert authenticates nothing to a victim.
Phase 2 moves the whole victim flow here: form, message submission, and
emergency-app checkins, all same-origin HTTP. Accepted risk, in writing:
victim traffic is plaintext over the air. In the threat model (file 09
section 1) victim-message INTEGRITY (protected by HMAC signing at ingest)
and AVAILABILITY outrank confidentiality on this plane. HTTPS 8443 remains
for every authenticated plane (api.py).

Controls on this open plane (file 09 plane 1):
  - strict input validation and size caps (pydantic models below)
  - per-IP AND global unauthenticated-write rate limits
  - no read-back of anyone else's data (no list endpoints here at all)
  - records signed with K_MSG at ingest (models.save_message/save_checkin)

Also serves the OS captive-portal probes (unchanged from Phase 1): any
probe URL returns the form page, which triggers the "sign in to network"
popup and lands victims directly on the message form.
"""

import html
from typing import List, Optional

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse
from pydantic import BaseModel, field_validator

import audit
import config
import models
import ratelimit

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
models.init_db()

audit_logger = audit.get_audit_logger()

_ip_limiter = ratelimit.SlidingWindowLimiter(
    config.RATE_LIMIT_COUNT, config.RATE_LIMIT_WINDOW_SECONDS, "per device"
)
_global_limiter = ratelimit.GlobalLimiter(
    config.GLOBAL_WRITE_LIMIT_COUNT, config.GLOBAL_WRITE_LIMIT_WINDOW_SECONDS, "network"
)


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "unknown"


def _enforce_public_write_limits(request: Request):
    _ip_limiter.check(_client_ip(request))
    _global_limiter.check_global()


# ---------------------------------------------------------------------------
# E2E victim encryption: capability kept, OFF by default (file 09 D2).
# ---------------------------------------------------------------------------

def _load_e2e_public_key() -> str:
    if not (config.E2E_ENABLED and config.VICTIM_E2E_PUBLIC_KEY_PATH):
        return ""
    from pathlib import Path
    p = Path(config.VICTIM_E2E_PUBLIC_KEY_PATH)
    if not p.exists():
        audit_logger.warning(f"E2E_KEY_MISSING | path={p}")
        return ""
    try:
        return p.read_text().strip()
    except OSError:
        audit_logger.warning(f"E2E_KEY_READ_FAIL | path={p}")
        return ""


VICTIM_E2E_PUBLIC_KEY = _load_e2e_public_key()


# ---------------------------------------------------------------------------
# Input models (Phase 1 validators carried over, extended to schema v3
# user_lat/user_lon; the free-text landmark is appended to content by the
# form BEFORE optional encryption, so there is no separate location field)
# ---------------------------------------------------------------------------

class MessageInput(BaseModel):
    is_encrypted: bool = False
    content: str
    encryption_alg: str = ""
    encryption_kid: str = ""
    victim_device_id: str = ""
    user_lat: Optional[float] = None
    user_lon: Optional[float] = None

    @field_validator("content")
    @classmethod
    def sanitize_content(cls, value, info):
        value = value.strip()
        if info.data.get("is_encrypted"):
            if not 1 <= len(value) <= 8192:
                raise ValueError("Encrypted content must be 1-8192 chars")
            import base64
            import binascii
            try:
                base64.b64decode(value, validate=True)
            except (binascii.Error, ValueError):
                raise ValueError("Encrypted content must be valid base64")
            return value
        if not 1 <= len(value) <= 800:
            raise ValueError("Content must be 1-800 chars")
        return html.escape(value)

    @field_validator("encryption_alg")
    @classmethod
    def sanitize_alg(cls, value, info):
        if not info.data.get("is_encrypted"):
            return ""
        return html.escape(value.strip()[:64]) if value else "RSA-OAEP-256"

    @field_validator("encryption_kid")
    @classmethod
    def sanitize_kid(cls, value, info):
        if not info.data.get("is_encrypted"):
            return ""
        return html.escape(value.strip()[:128]) if value else ""

    @field_validator("victim_device_id")
    @classmethod
    def sanitize_device_id(cls, value):
        return value.strip()[:64] if value else ""

    @field_validator("user_lat")
    @classmethod
    def validate_lat(cls, value):
        if value is not None and not -90 <= value <= 90:
            raise ValueError("Latitude must be -90..90")
        return value

    @field_validator("user_lon")
    @classmethod
    def validate_lon(cls, value):
        if value is not None and not -180 <= value <= 180:
            raise ValueError("Longitude must be -180..180")
        return value


class CheckinPoint(BaseModel):
    lat: float
    lon: float
    accuracy: Optional[float] = None
    recorded_at: str = ""

    @field_validator("lat")
    @classmethod
    def lat_range(cls, v):
        if not -90 <= v <= 90:
            raise ValueError("latitude out of range")
        return v

    @field_validator("lon")
    @classmethod
    def lon_range(cls, v):
        if not -180 <= v <= 180:
            raise ValueError("longitude out of range")
        return v

    @field_validator("accuracy")
    @classmethod
    def acc_ok(cls, v):
        if v is not None and v < 0:
            raise ValueError("accuracy must be non-negative")
        return v

    @field_validator("recorded_at")
    @classmethod
    def ts_cap(cls, v):
        return (v or "").strip()[:40]


class CheckinInput(BaseModel):
    device_id: str
    sos: bool = False
    sos_text: str = ""
    points: List[CheckinPoint] = []

    @field_validator("device_id")
    @classmethod
    def device_ok(cls, v):
        v = (v or "").strip()[:64]
        if not v:
            raise ValueError("device_id required")
        return v

    @field_validator("sos_text")
    @classmethod
    def sos_text_ok(cls, v):
        return html.escape((v or "").strip()[:500])

    @field_validator("points")
    @classmethod
    def points_cap(cls, v):
        if len(v) > 50:
            raise ValueError("too many points (max 50)")
        return v


# ---------------------------------------------------------------------------
# Victim form (Phase 1 form carried over; now same-origin HTTP, landmark
# text merged into the message before optional encryption, v3 field names)
# ---------------------------------------------------------------------------

VICTIM_FORM_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
    <title>Emergency Network</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f3f4f6;padding:16px}
        .card{background:#fff;border-radius:14px;padding:22px 18px;box-shadow:0 6px 18px rgba(0,0,0,.10);max-width:520px;margin:16px auto}
        .badge{display:inline-block;background:#dc2626;color:#fff;font-size:11px;font-weight:700;letter-spacing:.06em;padding:3px 8px;border-radius:99px;margin-bottom:10px}
        h1{font-size:20px;color:#b91c1c;margin-bottom:6px}
        .sub{font-size:14px;color:#374151;margin-bottom:16px;line-height:1.5}
        label{display:block;font-size:13px;font-weight:600;color:#374151;margin-bottom:5px}
        textarea,input[type=text]{width:100%;padding:10px;border:1px solid #d1d5db;border-radius:8px;font-size:15px;margin-bottom:12px}
        textarea{resize:vertical;min-height:100px}
        .btn{width:100%;padding:14px;border:none;border-radius:8px;font-size:16px;font-weight:700;cursor:pointer;margin-bottom:10px}
        .btn-loc{background:#fd7e14;color:#fff}
        .btn-loc.done{background:#16a34a}
        .btn-send{background:#dc2626;color:#fff}
        .btn-send:disabled{opacity:.6;cursor:not-allowed}
        #sessionId{font-size:12px;color:#6b7280;margin-bottom:14px;font-family:monospace}
        #locationStatus{font-size:12px;margin-top:-8px;margin-bottom:12px}
        .status-box{margin-top:14px;font-weight:600;padding:12px;border-radius:8px;display:none}
        .success{color:#155724;background:#d4edda}
        .error{color:#721c24;background:#f8d7da}
    </style>
</head>
<body>
<div class="card">
    <div class="badge">EMERGENCY NETWORK</div>
    <h1>Send Emergency Message</h1>
    <p class="sub">You are connected to a rescue drone. Fill in the form and tap <strong>SEND</strong>. Stay connected to this Wi-Fi and stay where you are.</p>
    <div id="sessionId"></div>

    <label for="content">Your situation / needs</label>
    <textarea id="content" placeholder="Describe your situation, injuries, or needs..." required></textarea>

    <button type="button" id="locBtn" class="btn btn-loc">Attach My GPS Location</button>
    <div id="locationStatus"></div>

    <label for="landmark">Location / Landmarks (optional)</label>
    <input type="text" id="landmark" placeholder="e.g. near the red barn, river crossing...">

    <input type="hidden" id="deviceId">
    <input type="hidden" id="userLat">
    <input type="hidden" id="userLon">

    <button class="btn btn-send" id="sendBtn" onclick="submitForm()">SEND MESSAGE</button>
    <div class="status-box" id="statusBox"></div>
</div>
<script>
function initDeviceId(){
    let id=localStorage.getItem('victim_device_id');
    if(!id){
        id='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{
            const r=Math.random()*16|0;
            return(c==='x'?r:(r&0x3|0x8)).toString(16);
        });
        localStorage.setItem('victim_device_id',id);
    }
    document.getElementById('deviceId').value=id;
    const s=id.substring(0,8)+'...'+id.substring(id.length-8);
    document.getElementById('sessionId').textContent='Session ID: '+s+' (show this to the rescue team)';
}

document.getElementById('locBtn').addEventListener('click',function(){
    const btn=this,status=document.getElementById('locationStatus');
    if(!navigator.geolocation){status.style.color='#856404';status.textContent='Geolocation not supported.';return;}
    btn.disabled=true;btn.textContent='Getting location...';
    status.style.color='#0c5460';status.textContent='Requesting permission...';
    navigator.geolocation.getCurrentPosition(
        pos=>{
            document.getElementById('userLat').value=pos.coords.latitude;
            document.getElementById('userLon').value=pos.coords.longitude;
            btn.textContent='Location Attached';btn.classList.add('done');
            status.style.color='#155724';
            status.textContent='GPS captured (+-'+Math.round(pos.coords.accuracy)+'m)';
        },
        err=>{
            const m={1:'Permission denied.',2:'Position unavailable.',3:'Timed out.'};
            status.style.color='#856404';status.textContent=m[err.code]||'Location error.';
            btn.textContent='Attach My GPS Location';btn.disabled=false;
        },
        {enableHighAccuracy:true,timeout:10000,maximumAge:0}
    );
});

async function fetchEncryptionConfig(){
    try{const r=await fetch('/victim-public-key');return r.ok?r.json():null;}catch{return null;}
}
function pemToBuffer(pem){
    const b64=pem.replace(/-----[^-]+-----/g,'').replace(/\\s+/g,'');
    const bin=atob(b64);const buf=new Uint8Array(bin.length);
    for(let i=0;i<bin.length;i++)buf[i]=bin.charCodeAt(i);
    return buf.buffer;
}
async function encryptMessage(text,pem){
    const key=await crypto.subtle.importKey('spki',pemToBuffer(pem),
        {name:'RSA-OAEP',hash:'SHA-256'},false,['encrypt']);
    const enc=await crypto.subtle.encrypt({name:'RSA-OAEP'},key,new TextEncoder().encode(text));
    return btoa(String.fromCharCode(...new Uint8Array(enc)));
}

async function submitForm(){
    const sendBtn=document.getElementById('sendBtn');
    const statusBox=document.getElementById('statusBox');
    let plaintext=document.getElementById('content').value.trim();
    if(!plaintext){
        statusBox.className='status-box error';
        statusBox.textContent='Please describe your situation before sending.';
        statusBox.style.display='block';return;
    }
    const landmark=document.getElementById('landmark').value.trim();
    if(landmark){plaintext=plaintext+' [Landmark: '+landmark.substring(0,200)+']';}
    sendBtn.textContent='SENDING...';sendBtn.disabled=true;statusBox.style.display='none';
    let content=plaintext,isEncrypted=false,encAlg='',encKid='';
    const cfg=await fetchEncryptionConfig();
    if(cfg&&cfg.public_key_pem){
        try{
            content=await encryptMessage(plaintext,cfg.public_key_pem);
            isEncrypted=true;encAlg=cfg.algorithm||'RSA-OAEP-256';encKid=cfg.kid||'';
        }catch(e){console.warn('Encryption failed, sending plaintext:',e);}
    }
    const lat=document.getElementById('userLat').value;
    const lon=document.getElementById('userLon').value;
    const payload={
        content,is_encrypted:isEncrypted,encryption_alg:encAlg,encryption_kid:encKid,
        victim_device_id:document.getElementById('deviceId').value,
        user_lat:lat?parseFloat(lat):null,
        user_lon:lon?parseFloat(lon):null,
    };
    try{
        const resp=await fetch('/message',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
        if(resp.ok){
            document.querySelector('.card').innerHTML="<h1 style='color:#16a34a;margin-bottom:12px;'>Message Sent</h1><p style='line-height:1.6;'>The drone will relay your message to the rescue team. Stay connected to this Wi-Fi and stay where you are.</p><p style='margin-top:12px;font-size:13px;color:#6b7280;'>Keep your Session ID: the rescue team will confirm with it when they find you.</p>";
        }else{
            const err=await resp.json().catch(()=>({}));
            statusBox.className='status-box error';
            statusBox.textContent='Error: '+(err.detail||'Failed to send. Please try again.');
            statusBox.style.display='block';
            sendBtn.textContent='SEND MESSAGE';sendBtn.disabled=false;
        }
    }catch{
        statusBox.className='status-box error';
        statusBox.textContent='Could not reach the drone. Check Wi-Fi and try again.';
        statusBox.style.display='block';
        sendBtn.textContent='SEND MESSAGE';sendBtn.disabled=false;
    }
}
document.addEventListener('DOMContentLoaded',initDeviceId);
</script>
</body>
</html>"""


def form_page() -> HTMLResponse:
    return HTMLResponse(content=VICTIM_FORM_HTML)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; script-src 'self' 'unsafe-inline'; "
        "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
        "connect-src 'self'; frame-ancestors 'none'"
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    return response


# ---------------------------------------------------------------------------
# Victim endpoints
# ---------------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse)
def root():
    return form_page()


@app.get("/victim-public-key")
def victim_public_key():
    if not VICTIM_E2E_PUBLIC_KEY:
        raise HTTPException(status_code=404, detail="Victim encryption not enabled")
    return {"public_key_pem": VICTIM_E2E_PUBLIC_KEY, "algorithm": "RSA-OAEP-256",
            "kid": config.VICTIM_E2E_KEY_ID}


@app.post("/message")
def post_victim_message(msg_input: MessageInput, request: Request):
    """Public victim submission: rate limited per-IP and globally, no key."""
    try:
        _enforce_public_write_limits(request)
        if models.count_messages_by_status("NEW") >= config.MAX_PENDING_MESSAGES:
            raise HTTPException(status_code=503, detail="Message intake temporarily full.")
        if config.E2E_ENCRYPTION_REQUIRED and not msg_input.is_encrypted:
            raise HTTPException(status_code=400, detail="This node requires encrypted messages.")
        msg_id = models.save_message(
            content=msg_input.content,
            user_lat=msg_input.user_lat,
            user_lon=msg_input.user_lon,
            is_encrypted=msg_input.is_encrypted,
            encryption_alg=msg_input.encryption_alg,
            encryption_kid=msg_input.encryption_kid,
            victim_device_id=msg_input.victim_device_id,
        )
        audit_logger.info(
            f"MESSAGE_CREATE | role=USER | ip={_client_ip(request)} | "
            f"msg_id={msg_id} | encrypted={msg_input.is_encrypted}"
        )
        return {"msg_id": msg_id, "status": "NEW"}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error while saving the message.")


@app.post("/checkin")
def post_checkin(checkin: CheckinInput, request: Request):
    """Emergency app upload (file 06): stored location points, optional SOS.
    An SOS also creates a normal message so it enters the rescue workflow
    (file 02 task 2.5)."""
    try:
        _enforce_public_write_limits(request)
        ids = []
        for point in checkin.points:
            ids.append(models.save_checkin(
                device_id=checkin.device_id,
                lat=point.lat, lon=point.lon,
                accuracy=point.accuracy,
                recorded_at=point.recorded_at or models.iso_now(),
                sos=1 if checkin.sos else 0,
            ))
        sos_msg_id = None
        if checkin.sos:
            latest = checkin.points[-1] if checkin.points else None
            content = checkin.sos_text or "SOS from emergency app"
            sos_msg_id = models.save_message(
                content=f"[SOS] {content}",
                user_lat=latest.lat if latest else None,
                user_lon=latest.lon if latest else None,
                victim_device_id=checkin.device_id,
            )
        audit_logger.info(
            f"CHECKIN | ip={_client_ip(request)} | device={checkin.device_id} | "
            f"points={len(ids)} | sos={checkin.sos}"
        )
        return JSONResponse({"stored": len(ids), "sos_msg_id": sos_msg_id})
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error while saving the checkin.")


@app.get("/probe")
def probe():
    """Connectivity probe for the emergency app (file 06): lets a phone
    confirm it is actually on a rescue drone AP before enabling SOS.

    The emergency app previously probed /health, which does not exist on
    this plane, so the catch-all returned the portal HTML and the app
    concluded it was NOT on a drone (bench finding 2026-07-13). This is a
    deliberate, minimal JSON endpoint: it exposes only what the phone
    already learned from the BLE advertisement (node id and SSID), and no
    victim data, keeping the open-plane no-read-back rule (file 09 plane 1).
    """
    return {"status": "ok", "node_id": config.NODE_ID, "ssid": config.USER_AP_SSID}


# ---------------------------------------------------------------------------
# OS captive portal probes (Phase 1 behavior kept: unexpected content on the
# probe URL triggers the "sign in to network" popup, which now lands victims
# directly on the message form)
# ---------------------------------------------------------------------------

@app.get("/generate_204")
def android_probe():
    return form_page()


@app.get("/hotspot-detect.html")
def ios_probe():
    return form_page()


@app.get("/ncsi.txt")
def windows_probe():
    return PlainTextResponse(content="Rescue Network Portal", status_code=200)


@app.get("/connecttest.txt")
def windows_probe_alt():
    return PlainTextResponse(content="Rescue Network Portal", status_code=200)


@app.get("/{path:path}", response_class=HTMLResponse)
def catch_all(path: str):
    api_paths = {"message", "checkin", "victim-public-key"}
    if path.split("/")[0] in api_paths:
        raise HTTPException(status_code=404, detail="Not found")
    return form_page()


if __name__ == "__main__":
    import uvicorn

    print(f"[*] Victim plane (HTTP) on {config.HTTP_HOST}:{config.HTTP_PORT}")
    uvicorn.run(app, host=config.HTTP_HOST, port=config.HTTP_PORT)
