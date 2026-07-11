"""
api.py — HTTPS-only application (port 8443)

Serves:
  - Victim message submission form  (GET /)  <- the real form, now on HTTPS
  - Victim message POST endpoint    (POST /message)
  - Rescue-team / HQ privileged API (/messages, /messages/{id}/claim, etc.)
  - Ground station dashboard        (/gs)
  - Inter-node sync                 (/messages GET with X-Node-Auth)

NOT served here:
  - Captive portal OS probes  -> http_app.py (port 8080)
  - Any plain HTTP traffic    -> http_app.py only
"""

from enum import Enum
from threading import Lock
import time
import html
import hmac
import logging
import base64
import binascii
import ssl
from typing import Optional, Set

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, validator
import models
import json
import os
from pathlib import Path

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
models.init_db()

static_path = Path(__file__).parent / "static"
if static_path.exists():
    app.mount("/static", StaticFiles(directory=str(static_path)), name="static")

gs_static_path = Path(__file__).parent / "groundControlCenter"
gs_index_path = gs_static_path / "index.html"


class Role(str, Enum):
    USER = "USER"
    RESCUE_TEAM = "RESCUE_TEAM"
    HQ = "HQ"
    SYNC_NODE = "SYNC_NODE"


ROLE_KEYS = {
    os.getenv("RESCUE_API_KEY", "rk_team_a_alpha"): Role.RESCUE_TEAM,
    os.getenv("HQ_API_KEY", "rk_hq_dashboard"): Role.HQ,
}
INTER_NODE_SECRET = os.getenv("INTER_NODE_SECRET", "mesh_change_me")
VICTIM_E2E_PUBLIC_KEY_PATH = os.getenv("VICTIM_E2E_PUBLIC_KEY_PATH", "")
VICTIM_E2E_KEY_ID = os.getenv("VICTIM_E2E_KEY_ID", "rescue-team-key-1")
E2E_ENCRYPTION_REQUIRED = os.getenv("E2E_ENCRYPTION_REQUIRED", "false").strip().lower() in {"1", "true", "yes", "on"}

RATE_LIMIT_COUNT = 5
RATE_LIMIT_WINDOW_SECONDS = 60
MAX_PENDING_MESSAGES = 10000

_rate_limit_store = {}
_rate_limit_lock = Lock()

AUDIT_LOG_FILE = os.getenv("AUDIT_LOG_FILE", "audit.log")
audit_logger = logging.getLogger("audit")
if not audit_logger.handlers:
    audit_logger.setLevel(logging.INFO)
    audit_handler = logging.FileHandler(AUDIT_LOG_FILE)
    audit_handler.setFormatter(logging.Formatter("%(asctime)s | %(levelname)s | %(message)s"))
    audit_logger.addHandler(audit_handler)


class MessageInput(BaseModel):
    is_encrypted: bool = False
    content: str
    location: str = ""
    origin_node: str = "UNKNOWN"
    encryption_alg: str = ""
    encryption_kid: str = ""
    victim_device_id: str = ""
    location_lat: Optional[float] = None
    location_lon: Optional[float] = None
    location_accuracy: Optional[float] = None
    location_timestamp: Optional[float] = None

    @validator("content")
    def sanitize_content(cls, value, values):
        value = value.strip()
        if values.get("is_encrypted"):
            if not 1 <= len(value) <= 8192:
                raise ValueError("Encrypted content must be 1–8192 chars")
            try:
                base64.b64decode(value, validate=True)
            except (binascii.Error, ValueError):
                raise ValueError("Encrypted content must be valid base64")
            return value
        if not 1 <= len(value) <= 500:
            raise ValueError("Content must be 1–500 chars")
        return html.escape(value)

    @validator("location")
    def sanitize_location(cls, value):
        return html.escape(value.strip()[:200]) if value else ""

    @validator("origin_node")
    def sanitize_origin_node(cls, value):
        s = value.strip()[:50] if value else "UNKNOWN"
        return html.escape(s) if s else "UNKNOWN"

    @validator("encryption_alg")
    def sanitize_encryption_alg(cls, value, values):
        if not values.get("is_encrypted"):
            return ""
        return html.escape(value.strip()[:64]) if value else "RSA-OAEP-256"

    @validator("encryption_kid")
    def sanitize_encryption_kid(cls, value, values):
        if not values.get("is_encrypted"):
            return ""
        return html.escape(value.strip()[:128]) if value else ""

    @validator("victim_device_id")
    def sanitize_victim_device_id(cls, value):
        return value.strip()[:64] if value else ""

    @validator("location_lat")
    def validate_lat(cls, value):
        if value is not None and not -90 <= value <= 90:
            raise ValueError("Latitude must be -90..90")
        return value

    @validator("location_lon")
    def validate_lon(cls, value):
        if value is not None and not -180 <= value <= 180:
            raise ValueError("Longitude must be -180..180")
        return value

    @validator("location_accuracy")
    def validate_accuracy(cls, value):
        if value is not None and value < 0:
            raise ValueError("Accuracy must be non-negative")
        return value


class GSMessageInput(BaseModel):
    content: str
    sender: str = "FIELD_TEAM"
    location_lat: Optional[float] = None
    location_lon: Optional[float] = None
    location_accuracy: Optional[float] = None
    location_timestamp: Optional[float] = None

    @validator("content")
    def sanitize_content(cls, value):
        value = value.strip()
        if not 1 <= len(value) <= 500:
            raise ValueError("Content must be 1–500 chars")
        return html.escape(value)

    @validator("location_lat")
    def lat_range(cls, v):
        if v is not None and not -90 <= v <= 90:
            raise ValueError("latitude out of range")
        return v

    @validator("location_lon")
    def lon_range(cls, v):
        if v is not None and not -180 <= v <= 180:
            raise ValueError("longitude out of range")
        return v

    @validator("location_accuracy")
    def accuracy_ok(cls, v):
        if v is not None and v < 0:
            raise ValueError("accuracy must be non-negative")
        return v

    @validator("sender")
    def sanitize_sender(cls, value):
        s = value.strip()[:100] if value else "FIELD_TEAM"
        return html.escape(s) if s else "FIELD_TEAM"


def get_role(
    x_api_key: Optional[str] = Header(default=None, alias="X-API-Key"),
    api_key: Optional[str] = Query(default=None),
    x_node_auth: Optional[str] = Header(default=None, alias="X-Node-Auth"),
) -> Role:
    # 1. Machine-to-Machine Check (Highest Priority)
    if x_node_auth is not None:
        if hmac.compare_digest(x_node_auth, INTER_NODE_SECRET):
            audit_logger.info("SYNC_AUTH_OK | auth=m2m_hmac")
            return Role.SYNC_NODE
        else:
            audit_logger.warning("SYNC_AUTH_FAIL | reason=bad_hmac")
            raise HTTPException(status_code=401, detail="Invalid inter-node auth")

    # 2. Human API Key Check
    key = x_api_key or api_key
    if key is None:
        return Role.USER
        
    role = ROLE_KEYS.get(key)
    if not role:
        audit_logger.warning("AUTH_FAIL | reason=invalid_api_key")
        raise HTTPException(status_code=401, detail="Invalid API key")
        
    return role


def require_roles(allowed_roles: Set[Role]):
    def _checker(role: Role = Depends(get_role)) -> Role:
        if role not in allowed_roles:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return role
    return _checker


def enforce_rate_limit(client_ip: str):
    now = time.time()
    window_start = now - RATE_LIMIT_WINDOW_SECONDS
    with _rate_limit_lock:
        ts = _rate_limit_store.get(client_ip, [])
        ts = [t for t in ts if t >= window_start]
        if len(ts) >= RATE_LIMIT_COUNT:
            raise HTTPException(status_code=429, detail="Rate limit exceeded. Please retry in a minute.")
        ts.append(now)
        _rate_limit_store[client_ip] = ts


def load_victim_e2e_public_key() -> str:
    if not VICTIM_E2E_PUBLIC_KEY_PATH:
        return ""
    p = Path(VICTIM_E2E_PUBLIC_KEY_PATH)
    if not p.exists():
        audit_logger.warning(f"E2E_KEY_MISSING | path={p}")
        return ""
    try:
        return p.read_text().strip()
    except OSError:
        audit_logger.warning(f"E2E_KEY_READ_FAIL | path={p}")
        return ""


VICTIM_E2E_PUBLIC_KEY = load_victim_e2e_public_key()

VICTIM_FORM_HTML = """<!DOCTYPE html>
<html lang="en">
<head>
    <title>Emergency Network</title>
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#f3f4f6;padding:16px}
        .card{background:#fff;border-radius:14px;padding:22px 18px;box-shadow:0 6px 18px rgba(0,0,0,.10);max-width:520px;margin:16px auto}
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
    <h1>🚨 Send Emergency Message</h1>
    <p class="sub">You are connected to a Rescue Drone. Fill in the form and tap <strong>SEND</strong>.</p>
    <div id="sessionId"></div>

    <label for="content">Your situation / needs</label>
    <textarea id="content" placeholder="Describe your situation, injuries, or needs..." required></textarea>

    <button type="button" id="locBtn" class="btn btn-loc">📍 Attach My GPS Location</button>
    <div id="locationStatus"></div>

    <label for="location">Location / Landmarks (optional)</label>
    <input type="text" id="location" placeholder="e.g. near the red barn, river crossing...">

    <input type="hidden" id="deviceId">
    <input type="hidden" id="locationLat">
    <input type="hidden" id="locationLon">
    <input type="hidden" id="locationAccuracy">
    <input type="hidden" id="locationTimestamp">

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
    document.getElementById('sessionId').textContent='Session ID: '+s+' — show this to the rescue team';
}

document.getElementById('locBtn').addEventListener('click',function(){
    const btn=this,status=document.getElementById('locationStatus');
    if(!navigator.geolocation){status.style.color='#856404';status.textContent='Geolocation not supported.';return;}
    btn.disabled=true;btn.textContent='Getting location...';
    status.style.color='#0c5460';status.textContent='Requesting permission...';
    navigator.geolocation.getCurrentPosition(
        pos=>{
            document.getElementById('locationLat').value=pos.coords.latitude;
            document.getElementById('locationLon').value=pos.coords.longitude;
            document.getElementById('locationAccuracy').value=pos.coords.accuracy;
            document.getElementById('locationTimestamp').value=Date.now()/1000;
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
    const b64=pem.replace(/-----[^-]+-----/g,'').replace(/\s+/g,'');
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
    const plaintext=document.getElementById('content').value.trim();
    if(!plaintext){
        statusBox.className='status-box error';
        statusBox.textContent='Please describe your situation before sending.';
        statusBox.style.display='block';return;
    }
    sendBtn.textContent='SENDING...';sendBtn.disabled=true;statusBox.style.display='none';
    let content=plaintext,isEncrypted=false,encAlg='',encKid='';
    const cfg=await fetchEncryptionConfig();
    if(cfg&&cfg.public_key_pem){
        try{
            content=await encryptMessage(plaintext,cfg.public_key_pem);
            isEncrypted=true;encAlg=cfg.algorithm||'RSA-OAEP-256';encKid=cfg.kid||'';
        }catch(e){console.warn('Encryption failed, sending plaintext:',e);}    
    }
    const lat=document.getElementById('locationLat').value;
    const lon=document.getElementById('locationLon').value;
    const payload={
        content,is_encrypted:isEncrypted,encryption_alg:encAlg,encryption_kid:encKid,
        location:document.getElementById('location').value,
        origin_node:'A',
        victim_device_id:document.getElementById('deviceId').value,
        location_lat:lat?parseFloat(lat):null,
        location_lon:lon?parseFloat(lon):null,
        location_accuracy:document.getElementById('locationAccuracy').value?parseFloat(document.getElementById('locationAccuracy').value):null,
        location_timestamp:document.getElementById('locationTimestamp').value?parseFloat(document.getElementById('locationTimestamp').value):null,
    };
    try{
        const resp=await fetch('/message',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
        if(resp.ok){
            document.querySelector('.card').innerHTML="<h1 style='color:#16a34a;margin-bottom:12px;'>Message Sent</h1><p style='line-height:1.6;'>The drone will relay your message to the rescue team. Stay connected to this Wi-Fi and stay where you are.</p><p style='margin-top:12px;font-size:13px;color:#6b7280;'>Keep your Session ID — the rescue team will confirm with it when they find you.</p>";
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


def gs_access_help_page() -> HTMLResponse:
    return HTMLResponse(content="""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Ground Station Access</title>
<style>body{font-family:sans-serif;background:#f8fafc;padding:24px}
.card{background:#fff;border-radius:12px;padding:20px;max-width:560px;margin:0 auto;box-shadow:0 4px 12px rgba(0,0,0,.08)}
h1{margin:0 0 8px}p{margin:8px 0;line-height:1.45}
input{width:100%;box-sizing:border-box;padding:10px;border-radius:8px;border:1px solid #d1d5db;margin-top:10px}
.btn{display:inline-block;padding:10px 14px;border-radius:8px;text-decoration:none;font-weight:600;margin-top:10px}
.danger{background:#dc2626;color:#fff}</style></head>
<body><div class="card"><h1>Ground Station (HQ) Access</h1>
<p>This endpoint is restricted to HQ operators. Enter your HQ API key:</p>
<form action="/gs" method="get"><input type="text" name="api_key" placeholder="Enter HQ API key"></form>
<p><a class="btn danger" href="/">Open Victim Portal</a></p>
</div></body></html>""", status_code=403)


@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Content-Security-Policy"] = (
        "default-src 'self' data: blob:; "
        "script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.tailwindcss.com https://cdn.jsdelivr.net https://fonts.googleapis.com; "
        "style-src 'self' 'unsafe-inline' https://cdn.tailwindcss.com https://cdn.jsdelivr.net https://fonts.googleapis.com https://fonts.gstatic.com; "
        "font-src 'self' https://fonts.gstatic.com; "
        "img-src 'self' data: https:; "
        "connect-src 'self' https://10.42.0.1:8443 https://localhost:8443 https://127.0.0.1:8443; "
        "media-src 'self' https:; "
        "frame-ancestors 'none'"
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


@app.get("/", response_class=HTMLResponse)
def root():
    return HTMLResponse(content=VICTIM_FORM_HTML)


@app.get("/victim-public-key")
def victim_public_key():
    if not VICTIM_E2E_PUBLIC_KEY:
        raise HTTPException(status_code=404, detail="Victim encryption key not configured")
    return {"public_key_pem": VICTIM_E2E_PUBLIC_KEY, "algorithm": "RSA-OAEP-256", "kid": VICTIM_E2E_KEY_ID}


@app.get("/gs", response_class=HTMLResponse)
def ground_station_root(role: Role = Depends(get_role)):
    if role != Role.HQ:
        return gs_access_help_page()
    if gs_index_path.exists():
        return HTMLResponse(content=gs_index_path.read_text())
    return HTMLResponse(content="<h1>Ground Station</h1><p>Dashboard not found</p>", status_code=404)


@app.get("/gs/", response_class=HTMLResponse)
def ground_station_slash(role: Role = Depends(get_role)):
    if role != Role.HQ:
        return gs_access_help_page()
    if gs_index_path.exists():
        return HTMLResponse(content=gs_index_path.read_text())
    return HTMLResponse(content="<h1>Ground Station</h1><p>Dashboard not found</p>", status_code=404)


@app.get("/messages")
def get_messages(
    role: Role = Depends(get_role),
    victim_device_id: Optional[str] = Query(default=None),
):
    try:
        # Explicitly authorize who can download messages
        if role not in {Role.RESCUE_TEAM, Role.HQ, Role.SYNC_NODE}:
            audit_logger.warning("AUTHZ_FAIL | endpoint=/messages | role=USER")
            raise HTTPException(status_code=403, detail="Insufficient permissions")
            
        if victim_device_id:
            msgs = models.get_messages_by_victim_device_id(victim_device_id)
            audit_logger.info(f"MESSAGE_QUERY | victim_device_id={victim_device_id} | count={len(msgs)}")
        else:
            msgs = models.get_all_messages()
        return JSONResponse(content=msgs)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


def _create_message(msg_input: MessageInput):
    msg_id = models.save_message(
        content=msg_input.content, location=msg_input.location,
        origin_node=msg_input.origin_node, is_encrypted=msg_input.is_encrypted,
        encryption_alg=msg_input.encryption_alg, encryption_kid=msg_input.encryption_kid,
        victim_device_id=msg_input.victim_device_id,
        location_lat=msg_input.location_lat, location_lon=msg_input.location_lon,
        location_accuracy=msg_input.location_accuracy, location_timestamp=msg_input.location_timestamp,
    )
    return {"msg_id": msg_id, "status": "NEW", "timestamp": 0}


@app.post("/message")
def post_portal_message(msg_input: MessageInput, request: Request):
    """Public victim submission — rate limited, no API key required."""
    try:
        client_ip = request.client.host if request.client else "unknown"
        enforce_rate_limit(client_ip)
        if models.count_messages_by_status("NEW") >= MAX_PENDING_MESSAGES:
            raise HTTPException(status_code=503, detail="Message intake temporarily full.")
        if E2E_ENCRYPTION_REQUIRED and not msg_input.is_encrypted:
            raise HTTPException(status_code=400, detail="This node requires encrypted messages.")
        created = _create_message(msg_input)
        audit_logger.info(f"MESSAGE_CREATE | role=USER | ip={client_ip} | msg_id={created['msg_id']} | encrypted={msg_input.is_encrypted}")
        return created
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/messages")
def post_message(msg_input: MessageInput, _: Role = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ}))):
    try:
        return _create_message(msg_input)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/messages/{msg_id}/claim")
def claim_message(msg_id: str, role: Role = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ}))):
    try:
        msg = models.get_message_by_id(msg_id)
        if not msg:
            raise HTTPException(status_code=404, detail="Message not found")
        models.claim_message(msg_id)
        audit_logger.info(f"CLAIM | role={role.value} | msg_id={msg_id}")
        return {"msg_id": msg_id, "status": "CLAIMED"}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/gs-uplink")
def post_gs_message(gs_input: GSMessageInput, role: Role = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ}))):
    try:
        msg_id = models.save_gs_message(
            content=gs_input.content, sender=gs_input.sender,
            location_lat=gs_input.location_lat, location_lon=gs_input.location_lon,
            location_accuracy=gs_input.location_accuracy, location_timestamp=gs_input.location_timestamp,
        )
        audit_logger.info(f"GS_UPLINK | role={role.value} | sender={gs_input.sender} | msg_id={msg_id}")
        return {"msg_id": msg_id, "status": "received"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/gs-messages")
def get_gs_messages(_: Role = Depends(require_roles({Role.HQ}))):
    try:
        return JSONResponse(content=models.get_gs_messages())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
def health_check():
    return {"status": "ok"}


@app.get("/{path:path}", response_class=HTMLResponse)
def catch_all(path: str):
    api_paths = {"messages","gs-messages","health","gs","message","gs-uplink","victim-public-key"}
    if path.split("/")[0] in api_paths:
        raise HTTPException(status_code=404, detail="Not found")
    return HTMLResponse(content=VICTIM_FORM_HTML)


if __name__ == "__main__":
    import uvicorn

    host = os.getenv("API_HOST", "10.42.0.1")
    tls_enabled = os.getenv("API_TLS_ENABLED", "false").strip().lower() in {"1", "true", "yes", "on"}
    default_port = 8443 if tls_enabled else 8000
    port = int(os.getenv("API_PORT", str(default_port)))

    if tls_enabled:
        cert_file = os.getenv("API_TLS_CERT", "cert.pem")
        key_file = os.getenv("API_TLS_KEY", "key.pem")
        mtls_enabled = os.getenv("API_MTLS_ENABLED", "false").strip().lower() in {"1", "true", "yes", "on"}
        mtls_ca_cert = os.getenv("API_MTLS_CA_CERT", "drone_ca.crt")
        if not (Path(cert_file).exists() and Path(key_file).exists()):
            raise RuntimeError("TLS enabled but cert/key not found.")
        if mtls_enabled and not Path(mtls_ca_cert).exists():
            raise RuntimeError("mTLS enabled but CA cert not found.")
        args = {"app": app, "host": host, "port": port, "ssl_certfile": cert_file, "ssl_keyfile": key_file}
        if mtls_enabled:
            args["ssl_cert_reqs"] = ssl.CERT_REQUIRED
            args["ssl_ca_certs"] = mtls_ca_cert
        uvicorn.run(**args)
    else:
        uvicorn.run(app, host=host, port=port)
