"""
api.py: the AUTHENTICATED plane, HTTPS on port 8443 (file 02 tasks 2.4/2.5,
file 09 planes 2 and 3).

Serves:
  - Rescue team / HQ API: messages, claims, gs uplink, announcements
  - Personnel management + PIN login -> stateless HMAC session tokens
  - Inter-node sync endpoints (/sync/*, SYNC_NODE role)
  - /health (public, real payload per design v3)

NOT served here (moved to http_app.py on port 80, file 09 F3):
  - Victim form, victim POST /message, emergency app POST /checkin

The Phase 1 /gs web dashboard is retired: it consumed the old schema and is
replaced by the GCC desktop app (file 04). Recorded in docs/CHANGES.md.

TLS: certs are issued by the fleet CA at deploy time (file 09 plane 2);
the rescue app and GCC embed the CA and fail closed against evil twins.
Static role keys remain as labeled break-glass credentials only.
"""

import html
import ssl
from enum import Enum
from pathlib import Path
from typing import Optional

from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.responses import HTMLResponse, JSONResponse
from pydantic import BaseModel, field_validator

import audit
import aux_state
import config
import crypto_keys
import models
import ratelimit

app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
models.init_db()

audit_logger = audit.get_audit_logger()

_login_ip_limiter = ratelimit.SlidingWindowLimiter(
    config.LOGIN_RATE_LIMIT_COUNT, config.LOGIN_RATE_LIMIT_WINDOW_SECONDS, "login per device"
)
_login_id_limiter = ratelimit.SlidingWindowLimiter(
    config.LOGIN_RATE_LIMIT_COUNT, config.LOGIN_RATE_LIMIT_WINDOW_SECONDS, "login per id"
)


class Role(str, Enum):
    USER = "USER"
    RESCUE_TEAM = "RESCUE_TEAM"
    HQ = "HQ"
    SYNC_NODE = "SYNC_NODE"


# Break-glass static keys (file 09 plane 2: demoted; primary path is PIN
# login for both rescue and HQ personnel).
ROLE_KEYS = {
    config.RESCUE_API_KEY: Role.RESCUE_TEAM,
    config.HQ_API_KEY: Role.HQ,
}


class Auth:
    """Resolved caller identity: role plus personnel_id when token-based."""

    def __init__(self, role: Role, personnel_id: str = "", via: str = ""):
        self.role = role
        self.personnel_id = personnel_id
        self.via = via


def get_auth(
    x_api_key: Optional[str] = Header(default=None, alias="X-API-Key"),
    api_key: Optional[str] = Query(default=None),
    x_node_auth: Optional[str] = Header(default=None, alias="X-Node-Auth"),
    x_session_token: Optional[str] = Header(default=None, alias="X-Session-Token"),
) -> Auth:
    import hmac as hmac_mod

    # 1. Machine-to-machine (highest priority): K_SYNC-derived shared value.
    if x_node_auth is not None:
        if hmac_mod.compare_digest(x_node_auth, crypto_keys.NODE_AUTH_VALUE):
            return Auth(Role.SYNC_NODE, via="node_auth")
        audit_logger.warning("SYNC_AUTH_FAIL | reason=bad_node_auth")
        raise HTTPException(status_code=401, detail="Invalid inter-node auth")

    # 2. Session token (primary human path, file 02 task 2.4). Valid token
    # AND an ACTIVE personnel record are both required, so revocation takes
    # effect at DTN sync latency without waiting for token expiry.
    if x_session_token:
        payload = crypto_keys.verify_token(x_session_token)
        if payload is None:
            audit_logger.warning("TOKEN_FAIL | reason=invalid_or_expired")
            raise HTTPException(status_code=401, detail="Session expired or invalid; log in again")
        record = models.get_personnel_by_id(payload["personnel_id"])
        if not record or record["status"] != "ACTIVE":
            audit_logger.warning(
                f"TOKEN_FAIL | personnel={payload['personnel_id']} | reason=revoked_or_unknown"
            )
            raise HTTPException(status_code=403, detail="Credentials revoked")
        role = Role.HQ if payload.get("role") == "HQ" else Role.RESCUE_TEAM
        return Auth(role, personnel_id=payload["personnel_id"], via="token")

    # 3. Break-glass static key.
    key = x_api_key or api_key
    if key is None:
        return Auth(Role.USER)
    role = ROLE_KEYS.get(key)
    if not role:
        audit_logger.warning("AUTH_FAIL | reason=invalid_api_key")
        raise HTTPException(status_code=401, detail="Invalid API key")
    return Auth(role, via="api_key")


def require_roles(allowed: set):
    def _checker(auth: Auth = Depends(get_auth)) -> Auth:
        if auth.role not in allowed:
            audit_logger.warning(f"AUTHZ_FAIL | role={auth.role.value}")
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        return auth
    return _checker


# ---------------------------------------------------------------------------
# Input models
# ---------------------------------------------------------------------------

class MessageInput(BaseModel):
    """Privileged message creation (rescue/HQ filing on behalf of someone)."""
    content: str
    user_lat: Optional[float] = None
    user_lon: Optional[float] = None
    victim_device_id: str = ""

    @field_validator("content")
    @classmethod
    def sanitize_content(cls, value):
        value = value.strip()
        if not 1 <= len(value) <= 800:
            raise ValueError("Content must be 1-800 chars")
        return html.escape(value)

    @field_validator("user_lat")
    @classmethod
    def lat_ok(cls, v):
        if v is not None and not -90 <= v <= 90:
            raise ValueError("latitude out of range")
        return v

    @field_validator("user_lon")
    @classmethod
    def lon_ok(cls, v):
        if v is not None and not -180 <= v <= 180:
            raise ValueError("longitude out of range")
        return v

    @field_validator("victim_device_id")
    @classmethod
    def dev_ok(cls, v):
        return (v or "").strip()[:64]


class GSMessageInput(BaseModel):
    content: str
    sender: str = "FIELD_TEAM"
    location_lat: Optional[float] = None
    location_lon: Optional[float] = None
    location_accuracy: Optional[float] = None
    location_timestamp: Optional[str] = None

    @field_validator("content")
    @classmethod
    def sanitize_content(cls, value):
        value = value.strip()
        if not 1 <= len(value) <= 500:
            raise ValueError("Content must be 1-500 chars")
        return html.escape(value)

    @field_validator("sender")
    @classmethod
    def sanitize_sender(cls, value):
        s = (value or "").strip()[:100]
        return html.escape(s) if s else "FIELD_TEAM"

    @field_validator("location_lat")
    @classmethod
    def lat_ok(cls, v):
        if v is not None and not -90 <= v <= 90:
            raise ValueError("latitude out of range")
        return v

    @field_validator("location_lon")
    @classmethod
    def lon_ok(cls, v):
        if v is not None and not -180 <= v <= 180:
            raise ValueError("longitude out of range")
        return v

    @field_validator("location_accuracy")
    @classmethod
    def acc_ok(cls, v):
        if v is not None and v < 0:
            raise ValueError("accuracy must be non-negative")
        return v


class PersonnelInput(BaseModel):
    name: str
    role: str = "RESCUE_TEAM"
    expires_hours: int = 0
    personnel_id: str = ""

    @field_validator("name")
    @classmethod
    def name_ok(cls, v):
        v = (v or "").strip()
        if not 1 <= len(v) <= 100:
            raise ValueError("Name must be 1-100 chars")
        return html.escape(v)

    @field_validator("role")
    @classmethod
    def role_ok(cls, v):
        if v not in {"RESCUE_TEAM", "HQ"}:
            raise ValueError("role must be RESCUE_TEAM or HQ")
        return v

    @field_validator("expires_hours")
    @classmethod
    def exp_ok(cls, v):
        if v < 0 or v > 24 * 365:
            raise ValueError("expires_hours out of range")
        return v

    @field_validator("personnel_id")
    @classmethod
    def pid_ok(cls, v):
        return (v or "").strip()[:32]


class LoginInput(BaseModel):
    personnel_id: str
    pin: str

    @field_validator("personnel_id")
    @classmethod
    def pid_ok(cls, v):
        v = (v or "").strip()[:32]
        if not v:
            raise ValueError("personnel_id required")
        return v

    @field_validator("pin")
    @classmethod
    def pin_ok(cls, v):
        v = (v or "").strip()
        if not 4 <= len(v) <= 16:
            raise ValueError("pin length invalid")
        return v


class AnnouncementInput(BaseModel):
    title: str
    body: str
    priority: str = "NORMAL"

    @field_validator("title")
    @classmethod
    def title_ok(cls, v):
        v = (v or "").strip()
        if not 1 <= len(v) <= 120:
            raise ValueError("Title must be 1-120 chars")
        return html.escape(v)

    @field_validator("body")
    @classmethod
    def body_ok(cls, v):
        v = (v or "").strip()
        if not 1 <= len(v) <= 2000:
            raise ValueError("Body must be 1-2000 chars")
        return html.escape(v)

    @field_validator("priority")
    @classmethod
    def prio_ok(cls, v):
        if v not in {"LOW", "NORMAL", "HIGH", "URGENT"}:
            raise ValueError("priority must be LOW/NORMAL/HIGH/URGENT")
        return v


class ClaimInput(BaseModel):
    claimed_by: str = ""

    @field_validator("claimed_by")
    @classmethod
    def cb_ok(cls, v):
        return html.escape((v or "").strip()[:64])


# ---------------------------------------------------------------------------
# Middleware
# ---------------------------------------------------------------------------

@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; frame-ancestors 'none'"
    )
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
    return response


@app.get("/", response_class=HTMLResponse)
def root():
    return HTMLResponse(content=f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>{config.NODE_ID} API</title></head>
<body style="font-family:sans-serif;padding:24px">
<h1>{config.NODE_ID}: authenticated API</h1>
<p>This port serves the rescue app, the GCC, and inter-node sync.</p>
<p>Victims: connect to the drone Wi-Fi and open
<a href="http://10.42.0.1/">http://10.42.0.1/</a> (opens automatically on
most phones).</p>
</body></html>""")


# ---------------------------------------------------------------------------
# Messages (rescue workflow)
# ---------------------------------------------------------------------------

@app.get("/messages")
def get_messages(
    auth: Auth = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ, Role.SYNC_NODE})),
    victim_device_id: Optional[str] = Query(default=None),
):
    try:
        if victim_device_id:
            msgs = models.get_messages_by_victim_device_id(victim_device_id)
            audit_logger.info(
                f"MESSAGE_QUERY | victim_device_id={victim_device_id} | count={len(msgs)}"
            )
        else:
            msgs = models.get_all_messages()
        return JSONResponse(content=msgs)
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error listing messages")


@app.post("/messages")
def post_message(
    msg_input: MessageInput,
    auth: Auth = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ})),
):
    try:
        msg_id = models.save_message(
            content=msg_input.content,
            user_lat=msg_input.user_lat,
            user_lon=msg_input.user_lon,
            victim_device_id=msg_input.victim_device_id,
        )
        audit_logger.info(f"MESSAGE_CREATE | role={auth.role.value} | msg_id={msg_id}")
        return {"msg_id": msg_id, "status": "NEW"}
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error saving message")


@app.post("/messages/{msg_id}/claim")
def claim_message(
    msg_id: str,
    claim: Optional[ClaimInput] = None,
    auth: Auth = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ})),
):
    try:
        msg = models.get_message_by_id(msg_id)
        if not msg:
            raise HTTPException(status_code=404, detail="Message not found")
        if msg["status"] == "CLAIMED":
            return {"msg_id": msg_id, "status": "CLAIMED",
                    "claimed_by": msg["claimed_by"], "already_claimed": True}
        # Identity precedence: token identity wins; body value is the
        # fallback for break-glass API key callers (file 05 task 5.2).
        claimed_by = auth.personnel_id or (claim.claimed_by if claim else "") or auth.role.value
        models.claim_message(msg_id, claimed_by)
        audit_logger.info(
            f"CLAIM | role={auth.role.value} | by={claimed_by} | msg_id={msg_id}"
        )
        return {"msg_id": msg_id, "status": "CLAIMED", "claimed_by": claimed_by}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error claiming message")


# ---------------------------------------------------------------------------
# GS messages (field reports)
# ---------------------------------------------------------------------------

@app.post("/gs-uplink")
def post_gs_message(
    gs_input: GSMessageInput,
    auth: Auth = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ})),
):
    try:
        sender = auth.personnel_id or gs_input.sender
        msg_id = models.save_gs_message(
            content=gs_input.content, sender=sender,
            location_lat=gs_input.location_lat, location_lon=gs_input.location_lon,
            location_accuracy=gs_input.location_accuracy,
            location_timestamp=gs_input.location_timestamp,
        )
        audit_logger.info(f"GS_UPLINK | role={auth.role.value} | sender={sender} | msg_id={msg_id}")
        return {"msg_id": msg_id, "status": "received"}
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error saving report")


@app.get("/gs-messages")
def get_gs_messages(auth: Auth = Depends(require_roles({Role.HQ, Role.SYNC_NODE}))):
    try:
        return JSONResponse(content=models.get_gs_messages())
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error listing reports")


# ---------------------------------------------------------------------------
# Personnel + PIN login (file 02 task 2.4)
# ---------------------------------------------------------------------------

@app.post("/personnel")
def create_personnel(
    p: PersonnelInput,
    auth: Auth = Depends(require_roles({Role.HQ})),
):
    try:
        record, pin = models.create_personnel(
            name=p.name, role=p.role, expires_hours=p.expires_hours,
            personnel_id=p.personnel_id,
        )
        audit_logger.info(
            f"PERSONNEL_CREATE | by={auth.personnel_id or 'api_key'} | "
            f"id={record['personnel_id']} | role={record['role']}"
        )
        # The plaintext PIN exists ONLY in this response (GCC shows it once).
        return {
            "personnel_id": record["personnel_id"],
            "name": record["name"],
            "role": record["role"],
            "expires_at": record["expires_at"],
            "pin": pin,
        }
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error creating personnel")


@app.get("/personnel")
def list_personnel(auth: Auth = Depends(require_roles({Role.HQ}))):
    try:
        return JSONResponse(content=models.get_personnel_public())
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error listing personnel")


@app.post("/personnel/{personnel_id}/revoke")
def revoke_personnel(
    personnel_id: str,
    auth: Auth = Depends(require_roles({Role.HQ})),
):
    try:
        ok = models.revoke_personnel(personnel_id)
        if not ok:
            raise HTTPException(status_code=404, detail="Personnel not found")
        audit_logger.info(
            f"PERSONNEL_REVOKE | by={auth.personnel_id or 'api_key'} | id={personnel_id}"
        )
        return {"personnel_id": personnel_id, "status": "REVOKED"}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error revoking personnel")


@app.post("/auth/login")
def login(login_input: LoginInput, request: Request):
    """PIN login -> stateless HMAC token verifiable offline by ANY node.
    Rate limited per IP AND per personnel_id (PINs are low entropy)."""
    client_ip = request.client.host if request.client else "unknown"
    _login_ip_limiter.check(client_ip)
    _login_id_limiter.check(login_input.personnel_id)
    record = models.verify_pin(login_input.personnel_id, login_input.pin)
    if record is None:
        audit_logger.warning(
            f"LOGIN_FAIL | id={login_input.personnel_id} | ip={client_ip}"
        )
        raise HTTPException(status_code=401, detail="Invalid credentials")
    token = crypto_keys.mint_token(record["personnel_id"], record["role"])
    audit_logger.info(
        f"LOGIN_OK | id={record['personnel_id']} | role={record['role']} | ip={client_ip}"
    )
    return {
        "token": token["token"],
        "expires_at": token["expires_at"],
        "personnel_id": record["personnel_id"],
        "role": record["role"],
        "name": record["name"],
    }


# ---------------------------------------------------------------------------
# Announcements. Decision (file 02 left GET scope open): rescue-scoped, not
# public. Announcements are operational guidance for rescue personnel; the
# victim plane has no read-back by design (file 09 plane 1). Recorded in
# docs/CHANGES.md item 8.
# ---------------------------------------------------------------------------

@app.get("/announcements")
def get_announcements(
    auth: Auth = Depends(require_roles({Role.RESCUE_TEAM, Role.HQ, Role.SYNC_NODE})),
):
    try:
        return JSONResponse(content=models.get_announcements())
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error listing announcements")


@app.post("/announcements")
def post_announcement(
    a: AnnouncementInput,
    auth: Auth = Depends(require_roles({Role.HQ})),
):
    try:
        ann_id = models.save_announcement(
            title=a.title, body=a.body, priority=a.priority,
            created_by=auth.personnel_id or "HQ",
        )
        audit_logger.info(f"ANNOUNCEMENT_CREATE | by={auth.personnel_id or 'api_key'} | id={ann_id}")
        return {"id": ann_id}
    except Exception:
        raise HTTPException(status_code=500, detail="Internal error saving announcement")


# ---------------------------------------------------------------------------
# Health (file 02 task 2.5: the real payload design v3 requires)
# ---------------------------------------------------------------------------

def _uptime_s() -> int:
    try:
        with open("/proc/uptime") as f:
            return int(float(f.read().split()[0]))
    except (OSError, ValueError, IndexError):
        return 0


@app.get("/health")
def health_check():
    state = aux_state.read_state()
    peers = models.alive_peers(config.PEER_EXPIRY)
    degraded = [h for h in models.latest_node_health() if h.get("degraded")]
    return {
        "status": "ok",
        "node_id": config.NODE_ID,
        "aux": "present" if state.get("aux_present") else "absent",
        "gps": state.get("gps"),
        "battery": state.get("battery"),
        "uptime_s": _uptime_s(),
        "clock_source": state.get("clock_source", "relative"),
        "message_counts": models.message_counts(),
        "table_counts": models.table_counts(),
        "peers": [
            {"node_id": p["node_id"], "ip": p["ip"], "last_seen": p["last_seen"]}
            for p in peers
        ],
        "degraded_nodes": [
            {"node_id": d["node_id"], "ts": d["ts"], "lat": d["lat"], "lon": d["lon"],
             "bat_a_v": d["bat_a_v"], "bat_b_v": d["bat_b_v"]}
            for d in degraded
        ],
    }


# ---------------------------------------------------------------------------
# Inter-node sync (file 02 task 2.3): delta endpoints for every replicated
# table. SYNC_NODE role only; per-record signatures are verified by the
# PULLING side (sync_engine.py), matching the Phase 1 trust direction.
# ---------------------------------------------------------------------------

def _sync_endpoint(table: str):
    def endpoint(
        since: str = Query(default=""),
        auth: Auth = Depends(require_roles({Role.SYNC_NODE})),
    ):
        try:
            rows = models.get_rows_since(table, since, config.SYNC_PAGE_LIMIT)
            return JSONResponse(content=rows)
        except Exception:
            raise HTTPException(status_code=500, detail=f"Internal error syncing {table}")
    return endpoint


app.get("/sync/messages")(_sync_endpoint("messages"))
app.get("/sync/personnel")(_sync_endpoint("personnel"))
app.get("/sync/announcements")(_sync_endpoint("announcements"))
app.get("/sync/gs-messages")(_sync_endpoint("gs_messages"))
app.get("/sync/checkins")(_sync_endpoint("checkins"))


if __name__ == "__main__":
    import uvicorn

    if config.API_TLS_ENABLED:
        cert_file = config.API_TLS_CERT
        key_file = config.API_TLS_KEY
        if not (Path(cert_file).exists() and Path(key_file).exists()):
            raise RuntimeError("TLS enabled but cert/key not found.")
        args = {
            "app": app,
            "host": config.API_HOST,
            "port": config.API_PORT,
            "ssl_certfile": cert_file,
            "ssl_keyfile": key_file,
        }
        # Inter-node mTLS: documented option, off by default (file 09 D1).
        if config.API_MTLS_ENABLED:
            if not Path(config.API_MTLS_CA_CERT).exists():
                raise RuntimeError("mTLS enabled but CA cert not found.")
            args["ssl_cert_reqs"] = ssl.CERT_REQUIRED
            args["ssl_ca_certs"] = config.API_MTLS_CA_CERT
        uvicorn.run(**args)
    else:
        uvicorn.run(app, host=config.API_HOST, port=config.API_PORT)
