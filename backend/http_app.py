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
import mission_config
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

# The victim portal. Rendered from the node's mission config so the options
# match the disaster (mission_config.py); a node never pushed to serves the
# stock need-based list.
#
# Design rules, all from tester feedback (CHANGES.md item 34). This page is
# read by someone frightened, possibly injured, on a cracked or wet screen,
# with a dying battery:
#   - Tapping beats typing. Nothing is required to be typed, ever.
#   - Location is ON by default. It is the single most useful thing for
#     finding them, so it is opt-OUT, not opt-in.
#   - Big type, big targets. No 13px labels.
#   - Say what happens next, and never imply a rescuer is already coming.
VICTIM_FORM_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
<title>Emergency: Get Help</title>
<style>
  *{box-sizing:border-box}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
       background:#f3f4f6;color:#111827;margin:0;padding:12px;font-size:17px;line-height:1.5}
  .card{background:#fff;border-radius:14px;padding:18px;max-width:640px;margin:0 auto;
        box-shadow:0 2px 10px rgba(0,0,0,.08)}
  .badge{display:inline-block;background:#dc2626;color:#fff;font-size:13px;font-weight:700;
         letter-spacing:.05em;padding:5px 11px;border-radius:99px}
  h1{font-size:26px;margin:12px 0 6px;line-height:1.25}
  .sub{font-size:17px;color:#374151;margin:0 0 18px}
  .opt{display:block;width:100%;text-align:left;background:#fff;border:2px solid #d1d5db;
       border-radius:12px;padding:16px 15px;margin-bottom:10px;font-size:18px;font-weight:600;
       color:#111827;cursor:pointer;min-height:60px}
  .opt:active{background:#f3f4f6}
  .opt.sel{border-color:#dc2626;background:#fef2f2;color:#991b1b}
  .opt .tick{float:right;font-size:20px;color:#dc2626;display:none}
  .opt.sel .tick{display:inline}
  .opt.urgent{border-left:8px solid #dc2626}
  .sec{font-size:15px;font-weight:700;color:#374151;margin:20px 0 8px;text-transform:uppercase;
       letter-spacing:.04em}
  textarea{width:100%;padding:13px;border:2px solid #d1d5db;border-radius:10px;font-size:17px;
           min-height:80px;font-family:inherit}
  .loc{border:2px solid #d1d5db;border-radius:12px;padding:14px;margin-top:8px;background:#f9fafb}
  .loc.on{border-color:#16a34a;background:#f0fdf4}
  .loc.off{border-color:#f59e0b;background:#fffbeb}
  .loc-t{font-weight:700;font-size:17px;margin-bottom:3px}
  .loc-s{font-size:15px;color:#4b5563}
  .linkbtn{background:none;border:none;color:#2563eb;font-size:15px;text-decoration:underline;
           padding:8px 0;cursor:pointer;font-family:inherit}
  .send{width:100%;background:#dc2626;color:#fff;border:none;border-radius:12px;padding:20px;
        font-size:22px;font-weight:800;margin-top:20px;cursor:pointer;min-height:68px;
        letter-spacing:.02em}
  .send:disabled{background:#9ca3af}
  .err{background:#fee2e2;color:#991b1b;padding:13px;border-radius:10px;margin-top:12px;
       font-weight:600;display:none}
  .ok-wrap{text-align:left}
  .ok-h{color:#16a34a;font-size:26px;margin:0 0 10px}
  .step{display:flex;gap:10px;margin:10px 0;font-size:16px}
  .step .n{flex-shrink:0;width:26px;height:26px;border-radius:50%;background:#16a34a;color:#fff;
           font-weight:700;text-align:center;line-height:26px;font-size:14px}
  .ref{margin-top:16px;padding:12px;background:#f3f4f6;border-radius:10px;font-size:15px}
  .ref b{font-size:20px;letter-spacing:.08em}
</style>
</head>
<body>
<div class="card" id="card">
  <div class="badge">EMERGENCY</div>
  <h1>Get help</h1>
  <p class="sub">__HEADLINE__</p>

  <div id="opts">__OPTIONS__</div>

  <div class="sec">Anything else? (you can skip this)</div>
  <textarea id="details" placeholder="Only if you can. Tapping above is enough."></textarea>

  <div class="sec">Your location</div>
  <div class="loc" id="locBox">
    <div class="loc-t" id="locTitle">Getting your location...</div>
    <div class="loc-s" id="locSub">This is the most important thing for finding you.</div>
    <button type="button" class="linkbtn" id="locToggle">Do not share my location</button>
  </div>

  <button class="send" id="sendBtn" disabled>SEND</button>
  <div class="err" id="err"></div>
</div>

<script>
var SEL = {};
var locOn = true, lat = null, lon = null, acc = null;

function deviceId(){
  var id = null;
  try { id = localStorage.getItem('victim_device_id'); } catch(e){}
  if(!id){
    id = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c){
      var r = Math.random()*16|0;
      return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
    });
    try { localStorage.setItem('victim_device_id', id); } catch(e){}
  }
  return id;
}

function refresh(){
  var any = Object.keys(SEL).length > 0 ||
            document.getElementById('details').value.trim().length > 0;
  document.getElementById('sendBtn').disabled = !any;
}

document.querySelectorAll('.opt').forEach(function(b){
  b.addEventListener('click', function(){
    var id = b.getAttribute('data-id');
    if(SEL[id]){ delete SEL[id]; b.classList.remove('sel'); }
    else { SEL[id] = b.getAttribute('data-label'); b.classList.add('sel'); }
    refresh();
  });
});
document.getElementById('details').addEventListener('input', refresh);

function locUI(state, title, sub){
  var box = document.getElementById('locBox');
  box.className = 'loc ' + state;
  document.getElementById('locTitle').textContent = title;
  document.getElementById('locSub').textContent = sub;
}

function askLocation(){
  if(!navigator.geolocation){
    locOn = false;
    locUI('off', 'Location not available on this phone',
          'Please describe where you are in the box above: a building name, a road, anything.');
    document.getElementById('locToggle').style.display = 'none';
    return;
  }
  locUI('', 'Getting your location...', 'Allow location if your phone asks.');
  navigator.geolocation.getCurrentPosition(
    function(pos){
      if(!locOn) return;
      lat = pos.coords.latitude; lon = pos.coords.longitude;
      acc = Math.round(pos.coords.accuracy);
      locUI('on', 'Location will be sent',
            'Accurate to about ' + acc + ' metres. This is how the team finds you.');
    },
    function(){
      locOn = false;
      locUI('off', 'Could not get your location',
            'Please type where you are in the box above: a building name, a road, a landmark.');
      document.getElementById('locToggle').textContent = 'Try location again';
    },
    {enableHighAccuracy:true, timeout:15000, maximumAge:60000}
  );
}

document.getElementById('locToggle').addEventListener('click', function(){
  if(locOn){
    locOn = false; lat = null; lon = null;
    locUI('off', 'Location will NOT be sent',
          'The team will have to search for you. Please describe where you are above.');
    this.textContent = 'Share my location';
  } else {
    locOn = true;
    this.textContent = 'Do not share my location';
    askLocation();
  }
});

document.getElementById('sendBtn').addEventListener('click', function(){
  var btn = this, err = document.getElementById('err');
  var labels = Object.keys(SEL).map(function(k){ return SEL[k]; });
  var details = document.getElementById('details').value.trim();
  var parts = [];
  if(labels.length) parts.push(labels.join('. '));
  if(details) parts.push(details);
  var content = parts.join(' -- ');
  if(!content){ return; }

  btn.textContent = 'SENDING...'; btn.disabled = true; err.style.display = 'none';
  fetch('/message', {
    method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({
      content: content,
      victim_device_id: deviceId(),
      user_lat: lat, user_lon: lon
    })
  }).then(function(r){
    if(r.ok){ return r.json().catch(function(){ return {}; }).then(sent); }
    return r.json().catch(function(){ return {}; }).then(function(e){
      throw new Error(e.detail || 'Could not send. Please try again.');
    });
  }).catch(function(e){
    err.textContent = e.message || 'Could not reach the drone. Stay on this Wi-Fi and try again.';
    err.style.display = 'block';
    btn.textContent = 'SEND'; btn.disabled = false;
  });
});

function sent(res){
  var ref = (res && res.msg_id ? String(res.msg_id) : deviceId())
              .replace(/-/g,'').slice(-4).toUpperCase();
  document.getElementById('card').innerHTML =
    '<div class="ok-wrap">' +
    '<div class="badge">SENT</div>' +
    '<h1 class="ok-h">Your message is on the drone</h1>' +
    '<div class="step"><span class="n">1</span><span>The drone has your message and has saved it.</span></div>' +
    '<div class="step"><span class="n">2</span><span>It carries the message to the rescue team. This can take a while if the drone must fly back, so do not worry if it is not instant.</span></div>' +
    '<div class="step"><span class="n">3</span><span>Stay where you are if it is safe. Keep this Wi-Fi on if you can.</span></div>' +
    '<div class="ref">Your reference: <b>' + ref + '</b><br>Tell the rescue team this if they ask.</div>' +
    '<button class="send" onclick="location.reload()" style="background:#374151">Send another message</button>' +
    '</div>';
}

document.addEventListener('DOMContentLoaded', function(){
  deviceId();
  askLocation();
  refresh();
});
</script>
</body>
</html>"""


def _render_options(cfg: dict) -> str:
    """Build the option buttons. Urgent ones first, since someone skimming
    reads the top of the list and may never reach the bottom."""
    situations = cfg.get("situations") or []
    ordered = sorted(situations, key=lambda s: not s.get("urgent"))
    out = []
    for s in ordered:
        sid = html.escape(str(s.get("id", "")), quote=True)
        label = html.escape(str(s.get("label", "")), quote=True)
        urgent = " urgent" if s.get("urgent") else ""
        out.append(
            f'<button type="button" class="opt{urgent}" data-id="{sid}" '
            f'data-label="{label}"><span class="tick">&#10003;</span>{label}</button>'
        )
    return "\n".join(out)


def form_page() -> HTMLResponse:
    cfg = mission_config.load()
    page = (VICTIM_FORM_TEMPLATE
            .replace("__OPTIONS__", _render_options(cfg))
            .replace("__HEADLINE__", html.escape(str(cfg.get("headline", "")))))
    return HTMLResponse(content=page)


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
