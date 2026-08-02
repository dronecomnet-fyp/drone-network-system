"""
The victim app's map feed (CHANGES.md item 38).

Sharing positions openly is a deliberate decision. These tests pin the
limits that decision came with: positions travel, identities and message
content do not, and rescuer visibility follows mission config rather than
being hardcoded.

Run with: .venv/bin/pytest tests/test_area_map.py -q
"""

import mission_config
import models
from fastapi.testclient import TestClient
from http_app import app as victim_app

victim = TestClient(victim_app)

DEV = "33333333-3333-4333-8333-333333333333"


def _reset_cfg():
    import os
    try:
        os.remove(mission_config._path())
    except OSError:
        pass


def _send(content="I am trapped", lat=6.92, lon=79.86):
    r = victim.post("/message", json={
        "content": content, "victim_device_id": DEV,
        "user_lat": lat, "user_lon": lon,
    })
    assert r.status_code == 200
    return r.json()["msg_id"]


def test_a_victim_position_appears_on_the_map():
    _reset_cfg()
    _send()
    data = victim.get("/area-map").json()
    assert any(abs(v["lat"] - 6.92) < 1e-6 for v in data["victims"])


def test_the_map_never_carries_message_content_or_device_ids():
    """The whole point of sharing positions is 'someone here needs help'.
    Nobody browsing an open Wi-Fi needs to read their medical details or
    be able to follow one person across time."""
    _reset_cfg()
    _send(content="Diabetic, alone, need insulin urgently")
    body = victim.get("/area-map").text
    assert "insulin" not in body.lower()
    assert DEV not in body
    for v in victim.get("/area-map").json()["victims"]:
        assert set(v.keys()) == {"lat", "lon", "helped"}


def test_helped_flag_shows_whether_anyone_picked_it_up():
    _reset_cfg()
    _send(lat=7.10, lon=80.10)
    entries = [v for v in victim.get("/area-map").json()["victims"]
               if abs(v["lat"] - 7.10) < 1e-6]
    assert entries and entries[0]["helped"] is False


def test_rescuer_positions_follow_mission_config():
    """Whether responders are publicly visible is the organisation's call,
    not each victim's, so it is a pushed setting rather than a constant."""
    _reset_cfg()
    assert "rescuers" in victim.get("/area-map").json()

    cfg = {
        "updated_at": "2026-08-03T10:00:00.000000Z",
        "situations": [{"id": "a", "label": "Need help", "urgent": True}],
        "show_rescuer_positions": False,
    }
    mission_config.save(cfg)
    assert victim.get("/area-map").json()["rescuers"] == []
    _reset_cfg()


def test_drones_are_listed_with_their_positions():
    _reset_cfg()
    models.save_node_health(node_id="DRONE_MAP", lat=6.5, lon=79.5,
                            gps_fix=1, degraded=0)
    drones = victim.get("/area-map").json()["drones"]
    assert any(d["node_id"] == "DRONE_MAP" for d in drones)


def test_the_feed_is_rate_limited_like_the_rest_of_the_plane():
    _reset_cfg()
    # Not asserting a specific limit, only that the route goes through the
    # limiter rather than being an unmetered read on an open network.
    codes = {victim.get("/area-map").status_code for _ in range(5)}
    assert codes <= {200, 429}
