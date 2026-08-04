"""
DEGRADED derivation and the enriched peer payload (CHANGES.md item 31).

Field bug this pins down: a single LoRa fallback beacon heard once marked a
node DOWN in the GCC forever, even while the fleet was actively syncing with
that node. /health must therefore DERIVE degraded from live evidence rather
than read back the stored flag.

Run with: .venv/bin/pytest tests/test_degraded_and_peers.py -q
"""

from datetime import datetime, timedelta, timezone

import config
import models
from api import app as auth_app
from fastapi.testclient import TestClient

authed = TestClient(auth_app)


def _iso_ago(seconds):
    return (datetime.now(timezone.utc) - timedelta(seconds=seconds)).strftime(
        "%Y-%m-%dT%H:%M:%S.%fZ"
    )


def _reset(node_id):
    conn = models.get_conn()
    conn.execute("DELETE FROM node_health WHERE node_id = ?", (node_id,))
    conn.execute("DELETE FROM peer_state WHERE node_id = ?", (node_id,))
    conn.commit()
    conn.close()


def _degraded_ids():
    r = authed.get("/health")
    assert r.status_code == 200
    return [d["node_id"] for d in r.json()["degraded_nodes"]]


def _peer(node_id):
    r = authed.get("/health")
    for p in r.json()["peers"]:
        if p["node_id"] == node_id:
            return p
    return None


def test_fresh_fallback_beacon_marks_node_degraded():
    _reset("DRONE_X")
    models.save_node_health(node_id="DRONE_X", lat=6.9, lon=79.9, degraded=1)
    assert "DRONE_X" in _degraded_ids()


def test_alive_peer_beats_a_fallback_beacon():
    """The exact reported bug: B is beaconing over DTN (its Pi is clearly
    alive) but an old LoRa beacon still claims it is down. Liveness wins."""
    _reset("DRONE_Y")
    models.save_node_health(node_id="DRONE_Y", lat=6.9, lon=79.9, degraded=1)
    assert "DRONE_Y" in _degraded_ids()

    models.accept_beacon("DRONE_Y", "10.99.0.9", config.API_PORT, 1, "{}")
    assert "DRONE_Y" not in _degraded_ids(), (
        "a node whose signed DTN beacon we are receiving must never be "
        "reported as DOWN"
    )


def test_stale_fallback_beacon_expires():
    """Beacons repeat every 30 s. Past FALLBACK_EXPIRY we have no evidence
    the node is down any more, so we stop asserting it."""
    _reset("DRONE_Z")
    models.save_node_health(
        node_id="DRONE_Z", lat=6.9, lon=79.9, degraded=1,
        ts=_iso_ago(config.FALLBACK_EXPIRY + 60),
    )
    assert "DRONE_Z" not in _degraded_ids()


def test_a_healthy_node_is_never_degraded():
    _reset("DRONE_W")
    models.save_node_health(node_id="DRONE_W", lat=6.9, lon=79.9, degraded=0)
    assert "DRONE_W" not in _degraded_ids()


def test_peer_carries_position_and_battery_with_its_own_age():
    """The peers table used to expose only node/ip/last_seen, so the GCC had
    nothing to plot. Cached health now rides along, with its own timestamp."""
    _reset("DRONE_P")
    models.accept_beacon("DRONE_P", "10.99.0.7", config.API_PORT, 1, "{}")
    models.save_node_health(
        node_id="DRONE_P", lat=6.9271, lon=79.8612, gps_fix=1,
        bat_a_v=7.8, bat_a_ma=590.0, bat_b_v=4.05, bat_b_ma=-500.0,
        uptime_s=1234, clock_source="gps", degraded=0,
    )
    p = _peer("DRONE_P")
    assert p is not None
    assert p["lat"] == 6.9271 and p["lon"] == 79.8612
    assert p["gps_fix"] == 1
    assert p["bat_a_v"] == 7.8
    # Signed, so a charging pack stays negative all the way to the UI.
    assert p["bat_b_ma"] == -500.0
    assert p["clock_source"] == "gps"
    assert p["health_ts"], "peer health must carry the age of the cached data"


def test_peer_without_cached_health_still_listed():
    """A peer on older code cannot be health-fetched. It must still appear
    as a peer, just with empty health, not vanish from the table."""
    _reset("DRONE_Q")
    models.accept_beacon("DRONE_Q", "10.99.0.8", config.API_PORT, 1, "{}")
    p = _peer("DRONE_Q")
    assert p is not None
    assert p["lat"] is None and p["health_ts"] is None


def test_node_health_history_is_bounded():
    """Health is written on a timer for us and every peer, so the table must
    not grow without limit on the SD card."""
    _reset("DRONE_R")
    for i in range(models.NODE_HEALTH_KEEP_ROWS + 25):
        models.save_node_health(node_id="DRONE_R", lat=1.0, lon=2.0,
                                ts=_iso_ago(10000 - i))
    conn = models.get_conn()
    n = conn.execute(
        "SELECT COUNT(*) c FROM node_health WHERE node_id = ?", ("DRONE_R",)
    ).fetchone()["c"]
    conn.close()
    assert n <= models.NODE_HEALTH_KEEP_ROWS


def test_revoking_a_rescuer_stops_them_being_tracked():
    """Field backlog #18: revoking someone left their location row in place,
    so the GCC went on counting and plotting them as a tracked rescuer."""
    conn = models.get_conn()
    conn.execute("DELETE FROM personnel_locations WHERE personnel_id = ?",
                 ("R_REVOKE",))
    conn.execute("DELETE FROM personnel WHERE personnel_id = ?", ("R_REVOKE",))
    conn.commit()
    conn.close()

    models.create_personnel("Revoked Rescuer", "RESCUE_TEAM",
                            personnel_id="R_REVOKE")
    models.save_personnel_location("R_REVOKE", 6.9, 79.9)
    ids = [p["personnel_id"] for p in models.get_personnel_locations()]
    assert "R_REVOKE" in ids

    models.revoke_personnel("R_REVOKE")
    ids = [p["personnel_id"] for p in models.get_personnel_locations()]
    assert "R_REVOKE" not in ids, "a revoked rescuer must stop being tracked"

    # The row itself is NOT deleted: it still replicates, and an operator
    # can still ask for it deliberately.
    all_ids = [p["personnel_id"]
               for p in models.get_personnel_locations(include_inactive=True)]
    assert "R_REVOKE" in all_ids


def test_a_location_for_unknown_personnel_is_kept():
    """Personnel sync can lag behind location sync. Dropping a real
    rescuer's position because their record has not arrived yet would hide
    someone who is out there working: unknown is not the same as revoked."""
    conn = models.get_conn()
    conn.execute("DELETE FROM personnel WHERE personnel_id = ?", ("R_UNKNOWN",))
    conn.commit()
    conn.close()
    models.save_personnel_location("R_UNKNOWN", 6.5, 79.5)
    ids = [p["personnel_id"] for p in models.get_personnel_locations()]
    assert "R_UNKNOWN" in ids
