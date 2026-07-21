"""
API surface tests for both planes (file 02 acceptance + file 09 T9.2/T9.5
local equivalents). Run with: .venv/bin/pytest tests/ -q
"""

import json
import os

import pytest
from fastapi.testclient import TestClient

import api
import aux_state
import config
import crypto_keys
import models
import ratelimit
from http_app import app as victim_app
from api import app as auth_app

victim = TestClient(victim_app)
authed = TestClient(auth_app)

HQ = {"X-API-Key": "test_hq_key"}
RESCUE = {"X-API-Key": "test_rescue_key"}
NODE = {"X-Node-Auth": crypto_keys.NODE_AUTH_VALUE}


# ---------------------------------------------------------------------------
# Victim plane (port 80 app)
# ---------------------------------------------------------------------------

def test_victim_form_served():
    r = victim.get("/")
    assert r.status_code == 200
    assert "Send Emergency Message" in r.text or "SEND MESSAGE" in r.text


def test_captive_probes():
    assert victim.get("/generate_204").status_code == 200
    assert victim.get("/hotspot-detect.html").status_code == 200
    assert "Rescue Network Portal" in victim.get("/ncsi.txt").text


def test_victim_message_post_and_signature():
    r = victim.post("/message", json={
        "content": "trapped near the bridge",
        "user_lat": 6.9271, "user_lon": 79.8612,
        "victim_device_id": "test-device-1",
    })
    assert r.status_code == 200, r.text
    msg_id = r.json()["msg_id"]
    stored = models.get_message_by_id(msg_id)
    assert stored["status"] == "NEW"
    assert stored["node_id"] == "DRONE_T"
    assert stored["time_source"] in {"relative", "gps"}
    assert models.verify_record("messages", stored)


def test_victim_public_key_404_when_e2e_disabled():
    # E2E is OFF by default (file 09 D2)
    assert victim.get("/victim-public-key").status_code == 404


def test_checkin_with_sos_creates_message():
    r = victim.post("/checkin", json={
        "device_id": "emg-1",
        "sos": True,
        "sos_text": "stuck on roof",
        "points": [
            {"lat": 6.90, "lon": 79.86, "accuracy": 12.0, "recorded_at": "2026-07-11T01:00:00Z"},
            {"lat": 6.91, "lon": 79.87, "accuracy": 8.0, "recorded_at": "2026-07-11T13:00:00Z"},
        ],
    })
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["stored"] == 2
    sos_msg = models.get_message_by_id(body["sos_msg_id"])
    assert sos_msg is not None and "[SOS]" in sos_msg["content"]
    assert sos_msg["user_lat"] == 6.91  # newest point attached
    checkins = models.get_checkins()
    assert all(models.verify_record("checkins", c) for c in checkins)
    # read-back lives on the authenticated plane (GCC map layer), not here
    listing = authed.get("/checkins", headers=RESCUE)
    assert listing.status_code == 200
    assert any(c["device_id"] == "emg-1" for c in listing.json())
    assert authed.get("/checkins").status_code == 403


def test_victim_plane_has_no_read_endpoints():
    # file 09 plane 1: no read-back on the open plane
    assert victim.post("/message", json={"content": ""}).status_code in {400, 422}
    r = victim.get("/messages")
    assert "msg_id" not in r.text  # catch-all serves the form, not data


# ---------------------------------------------------------------------------
# Rate limiting (limiter unit behavior + login endpoint integration)
# ---------------------------------------------------------------------------

def test_limiter_unit_429():
    from fastapi import HTTPException
    lim = ratelimit.SlidingWindowLimiter(3, 60, "unit")
    for _ in range(3):
        lim.check("k")
    with pytest.raises(HTTPException) as e:
        lim.check("k")
    assert e.value.status_code == 429
    lim.check("other-key")  # other keys unaffected


def test_global_limiter_unit():
    from fastapi import HTTPException
    lim = ratelimit.GlobalLimiter(2, 60, "global unit")
    lim.check_global()
    lim.check_global()
    with pytest.raises(HTTPException):
        lim.check_global()


# ---------------------------------------------------------------------------
# Auth lifecycle (file 02 acceptance 2, file 07 T4, T9.2)
# ---------------------------------------------------------------------------

def test_personnel_lifecycle_and_tokens():
    # create (HQ role required)
    r = authed.post("/personnel", json={"name": "Bob Fields", "role": "RESCUE_TEAM"},
                    headers=HQ)
    assert r.status_code == 200, r.text
    created = r.json()
    pid, pin = created["personnel_id"], created["pin"]
    assert pid.startswith("R-") and len(pin) == config.PIN_LENGTH

    # list has no hash material
    listing = authed.get("/personnel", headers=HQ).json()
    assert all("pin_hash" not in row and "pin_salt" not in row for row in listing)

    # rescue role cannot create personnel
    assert authed.post("/personnel", json={"name": "X"}, headers=RESCUE).status_code == 403

    # login
    r = authed.post("/auth/login", json={"personnel_id": pid, "pin": pin})
    assert r.status_code == 200, r.text
    token = r.json()["token"]
    TOK = {"X-Session-Token": token}

    # token works on privileged endpoints
    assert authed.get("/messages", headers=TOK).status_code == 200
    # but not on HQ-only endpoints (role separation)
    assert authed.get("/personnel", headers=TOK).status_code == 403

    # claim uses the token identity as claimed_by (file 05 task 5.2)
    msg_id = models.save_message("victim message for claim test")
    r = authed.post(f"/messages/{msg_id}/claim", headers=TOK)
    assert r.status_code == 200
    assert r.json()["claimed_by"] == pid
    # double claim reports already_claimed, keeps original claimer
    r2 = authed.post(f"/messages/{msg_id}/claim", headers=RESCUE)
    assert r2.json().get("already_claimed") is True
    assert r2.json()["claimed_by"] == pid

    # revoke: token dies at next use even before expiry. 401, not 403: the
    # CREDENTIAL is dead, so the client must re-authenticate. 403 means
    # "logged in fine, wrong role" and must never log anyone out.
    assert authed.post(f"/personnel/{pid}/revoke", headers=HQ).status_code == 200
    assert authed.get("/messages", headers=TOK).status_code == 401
    # new login also fails
    assert authed.post("/auth/login",
                       json={"personnel_id": pid, "pin": pin}).status_code == 401


def test_personnel_location_heartbeat(monkeypatch):
    # A logged-in rescuer posts a location; it is stored under their token
    # identity (not the body) and read back by the rescue/GCC plane. (M7d)
    created = authed.post("/personnel", json={"name": "Mover", "role": "RESCUE_TEAM"},
                          headers=HQ).json()
    pid, pin = created["personnel_id"], created["pin"]
    api._login_ip_limiter._events.clear()
    token = authed.post("/auth/login",
                        json={"personnel_id": pid, "pin": pin}).json()["token"]
    TOK = {"X-Session-Token": token}

    r = authed.post("/personnel-location",
                    json={"lat": 6.91, "lon": 79.86, "accuracy_m": 12.0,
                          "battery_pct": 77}, headers=TOK)
    assert r.status_code == 200, r.text
    assert r.json()["personnel_id"] == pid

    listing = authed.get("/personnel-locations", headers=TOK).json()
    mine = [row for row in listing if row["personnel_id"] == pid]
    assert len(mine) == 1
    assert mine[0]["lat"] == 6.91 and mine[0]["battery_pct"] == 77
    assert mine[0]["node_id"] == config.NODE_ID
    assert mine[0]["signature"]  # stored signed

    # Out-of-range coordinates are rejected by validation.
    assert authed.post("/personnel-location",
                       json={"lat": 200, "lon": 0}, headers=TOK).status_code == 422

    # Break-glass API-key callers have no personnel identity: refused.
    assert authed.post("/personnel-location",
                       json={"lat": 6.9, "lon": 79.8}, headers=RESCUE).status_code == 403


def test_token_forgery_and_expiry_rejected():
    # forged with a wrong key (T9.2)
    import base64
    import hashlib
    import hmac as hmac_mod
    import time as time_mod
    payload = json.dumps({"exp": int(time_mod.time()) + 3600,
                          "personnel_id": "R-999", "role": "RESCUE_TEAM"},
                         separators=(",", ":"), sort_keys=True)
    body = base64.urlsafe_b64encode(payload.encode()).decode().rstrip("=")
    bad_sig = hmac_mod.new(b"wrong-key", payload.encode(), hashlib.sha256).hexdigest()
    r = authed.get("/messages", headers={"X-Session-Token": f"{body}.{bad_sig}"})
    assert r.status_code == 401

    # expired
    expired = crypto_keys.mint_token("R-998", "RESCUE_TEAM", ttl_hours=-1)
    r = authed.get("/messages", headers={"X-Session-Token": expired["token"]})
    assert r.status_code == 401

    # Valid signature but personnel record does not exist: the credential
    # names nobody, so it is dead (401), not merely forbidden.
    ghost = crypto_keys.mint_token("R-000-ghost", "RESCUE_TEAM")
    r = authed.get("/messages", headers={"X-Session-Token": ghost["token"]})
    assert r.status_code == 401


def test_login_rate_limit():
    # Reset the per-IP bucket (earlier tests logged in from the same test
    # client IP); this test targets the per-personnel_id limiter exactly.
    api._login_ip_limiter._events.clear()
    rec, _pin = models.create_personnel("Rate Limit Target")
    for i in range(5):
        r = authed.post("/auth/login",
                        json={"personnel_id": rec["personnel_id"], "pin": "999999"})
        assert r.status_code == 401
    r = authed.post("/auth/login",
                    json={"personnel_id": rec["personnel_id"], "pin": "999999"})
    assert r.status_code == 429  # five wrong PINs trigger the limit (T4)


# ---------------------------------------------------------------------------
# Announcements (decision: rescue-scoped GET)
# ---------------------------------------------------------------------------

def test_announcements_round_trip():
    r = authed.post("/announcements",
                    json={"title": "Water point", "body": "North shelter has water",
                          "priority": "HIGH"}, headers=HQ)
    assert r.status_code == 200, r.text
    # rescue role can read
    listing = authed.get("/announcements", headers=RESCUE).json()
    assert any(a["title"] == "Water point" for a in listing)
    assert all(models.verify_record("announcements", a) for a in listing)
    # unauthenticated cannot read (rescue-scoped decision, CHANGES.md item 8)
    assert authed.get("/announcements").status_code == 403
    # rescue role cannot post
    assert authed.post("/announcements",
                       json={"title": "x", "body": "y"}, headers=RESCUE).status_code == 403


# ---------------------------------------------------------------------------
# Health (file 02 task 2.5)
# ---------------------------------------------------------------------------

def test_health_reads_aux_state():
    state = dict(aux_state.DEFAULT_STATE)
    state.update({
        "aux_present": True,
        "gps": {"lat": 6.93, "lon": 79.85, "fix": 1, "sats": 7, "hdop": 1.2},
        "battery": {"a_v": 7.9, "a_ma": 610.0, "b_v": 4.0, "b_ma": 140.0},
        "gps_time_applied": True,
        "clock_source": "gps",
    })
    aux_state.write_state(state)
    h = authed.get("/health").json()
    assert h["node_id"] == "DRONE_T"
    assert h["aux"] == "present"
    assert h["gps"]["sats"] == 7
    assert h["battery"]["a_v"] == 7.9
    assert h["clock_source"] == "gps"
    assert "message_counts" in h and "peers" in h
    # reset to absent for other tests
    aux_state.write_state(dict(aux_state.DEFAULT_STATE))


def test_rescuer_can_read_the_field_reports_they_file():
    """Regression (bench finding 2026-07-14): the rescue app's HQ Uplink
    screen lists gs_messages under its compose box, but this endpoint was
    HQ-only. A rescuer opening that tab got a 403, which the app treated as
    'credentials revoked' and logged them out of the whole app."""
    # Earlier tests exhausted the per-IP login limiter (all tests share one
    # client IP); this test is not about rate limiting.
    api._login_ip_limiter._events.clear()
    rec, pin = models.create_personnel("Field Reporter")
    token = authed.post(
        "/auth/login",
        json={"personnel_id": rec["personnel_id"], "pin": pin},
    ).json()["token"]
    tok = {"X-Session-Token": token}

    # A rescuer can file a report AND read the log back.
    assert authed.post("/gs-uplink", json={"content": "culvert washed out"},
                       headers=tok).status_code == 200
    listing = authed.get("/gs-messages", headers=tok)
    assert listing.status_code == 200
    assert any("culvert washed out" in g["content"] for g in listing.json())

    # A role denial stays a 403 and is NOT a dead credential: the very same
    # token must still work on the endpoints the rescuer IS allowed to use.
    assert authed.get("/personnel", headers=tok).status_code == 403
    assert authed.get("/messages", headers=tok).status_code == 200


# ---------------------------------------------------------------------------
# Sync endpoints (file 02 task 2.3)
# ---------------------------------------------------------------------------

def test_sync_requires_node_auth():
    assert authed.get("/sync/messages").status_code == 403
    assert authed.get("/sync/messages",
                      headers={"X-Node-Auth": "wrong"}).status_code == 401
    r = authed.get("/sync/messages", headers=NODE)
    assert r.status_code == 200
    rows = r.json()
    assert isinstance(rows, list) and len(rows) >= 1
    assert "local_ts" in rows[0] and "signature" in rows[0]


def test_sync_since_filters():
    r = authed.get("/sync/messages", headers=NODE)
    rows = r.json()
    latest = max(row["local_ts"] for row in rows)
    r2 = authed.get("/sync/messages", params={"since": latest}, headers=NODE)
    assert r2.json() == []
    # personnel sync DOES include hash material (nodes need it to verify
    # logins offline); it is SYNC_NODE-scoped
    p = authed.get("/sync/personnel", headers=NODE).json()
    assert len(p) >= 1 and "pin_hash" in p[0]


def test_gs_uplink_and_sync():
    r = authed.post("/gs-uplink", json={"content": "bridge collapsed",
                                        "location_lat": 6.95, "location_lon": 79.86},
                    headers=RESCUE)
    assert r.status_code == 200
    rows = authed.get("/sync/gs-messages", headers=NODE).json()
    assert any("bridge collapsed" in row["content"] for row in rows)
    assert all(models.verify_record("gs_messages", row) for row in rows)
