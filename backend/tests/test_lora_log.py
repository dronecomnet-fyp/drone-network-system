"""
The LoRa event log (field backlog #13).

The operator asked for a tab that logs every LoRa message, because
/health's degraded list only ever answers "is that drone down right now".
That is the wrong question when you are deciding whether to walk out to a
drone: you want to know what it told you, when, and how well you were
hearing it.

Two properties are worth pinning down. The log must REPLICATE, because the
node that hears a beacon is whichever one is nearest the failure and HQ
may be joined to a different one. And a frame that comes back to us from a
peer that also heard it must not appear twice as if it were two frames.

Run with: .venv/bin/pytest tests/test_lora_log.py -q
"""

import config
import models
import sync_engine
from api import app as auth_app
from fastapi.testclient import TestClient

authed = TestClient(auth_app)
HQ = {"X-API-Key": "test_hq_key"}
RESCUE = {"X-API-Key": "test_rescue_key"}

BEACON = ("FB|DRONE_B|6.9271|79.8612|1|2026-08-05T09:00:00Z|4.02|310|"
          "3.98|280|m-17|two adults on a roof|2026-08-05T08:58:00Z|DOWN")


def _reset():
    conn = models.get_conn()
    conn.execute("DELETE FROM lora_events")
    conn.commit()
    conn.close()


def test_a_heard_beacon_becomes_a_readable_log_entry():
    _reset()
    models.save_lora_event(
        kind="fallback", about_node="DRONE_B", raw=BEACON,
        rssi=-97.0, snr=6.5, lat=6.9271, lon=79.8612, gps_fix=1,
        bat_a_v=4.02, bat_b_v=3.98, last_msg="two adults on a roof",
    )
    events = authed.get("/lora-events", headers=HQ).json()["events"]
    assert len(events) == 1
    e = events[0]
    assert e["about_node"] == "DRONE_B"
    assert e["heard_by"] == config.NODE_ID
    assert e["rssi"] == -97.0
    assert e["last_msg"] == "two adults on a roof"
    assert e["kind"] == "fallback"


def test_rescuers_may_read_the_log_too():
    """A rescuer standing near a dead drone is the person best placed to
    act on this, so it is not HQ only."""
    _reset()
    models.save_lora_event(kind="fallback", about_node="DRONE_B", raw=BEACON)
    assert authed.get("/lora-events", headers=RESCUE).status_code == 200


def test_the_log_reaches_a_node_that_never_heard_the_beacon():
    """The whole reason this table replicates, unlike node_health."""
    _reset()
    record = models.save_lora_event(
        kind="fallback", about_node="DRONE_B", raw=BEACON, rssi=-97.0)
    _reset()
    assert authed.get("/lora-events", headers=HQ).json()["events"] == []

    full = dict(record)
    full.update({"rssi": -97.0, "snr": None, "lat": None, "lon": None,
                 "gps_fix": 0, "bat_a_v": None, "bat_b_v": None,
                 "last_msg": "", "node_id": record["heard_by"]})
    assert sync_engine.ingest_lora_event(full, "DRONE_A") == "inserted"
    assert len(authed.get("/lora-events", headers=HQ).json()["events"]) == 1


def test_the_same_frame_coming_back_does_not_duplicate():
    _reset()
    record = models.save_lora_event(
        kind="fallback", about_node="DRONE_B", raw=BEACON)
    full = dict(record)
    full.update({"rssi": None, "snr": None, "lat": None, "lon": None,
                 "gps_fix": 0, "bat_a_v": None, "bat_b_v": None,
                 "last_msg": "", "node_id": record["heard_by"]})
    sync_engine.ingest_lora_event(full, "DRONE_A")
    sync_engine.ingest_lora_event(full, "DRONE_A")
    assert len(authed.get("/lora-events", headers=HQ).json()["events"]) == 1


def test_a_forged_entry_is_rejected_like_any_other_record():
    """Nothing is trusted because it arrived over sync. A node that can
    invent LoRa events can invent a drone failure."""
    _reset()
    record = models.save_lora_event(
        kind="fallback", about_node="DRONE_B", raw=BEACON)
    forged = dict(record)
    forged.update({"about_node": "DRONE_A", "rssi": None, "snr": None,
                   "lat": None, "lon": None, "gps_fix": 0, "bat_a_v": None,
                   "bat_b_v": None, "last_msg": "", "id": "forged-1",
                   "node_id": record["heard_by"]})
    assert sync_engine.ingest_lora_event(forged, "DRONE_A") == "rejected"


def test_the_log_is_pruned_rather_than_growing_without_bound():
    """A node down for a day beacons roughly 2900 times."""
    _reset()
    for i in range(12):
        models.save_lora_event(
            kind="fallback", about_node="DRONE_B", raw=f"{BEACON}|{i}")
    assert models.prune_lora_events(keep=5) == 7
    assert len(models.get_lora_events()) == 5
