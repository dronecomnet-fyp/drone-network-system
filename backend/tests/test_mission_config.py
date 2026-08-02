"""
Versioned victim-portal config pushed from the GCC (CHANGES.md item 34).

The properties worth protecting are all about a PARTIALLY updated fleet,
which is the normal state during a rollout: a node nobody reached must
still serve something useful, an operator must be able to see which nodes
are actually updated, and a stale GCC must not be able to undo a newer
push from another operator.

Run with: .venv/bin/pytest tests/test_mission_config.py -q
"""

import mission_config
from api import app as auth_app
from fastapi.testclient import TestClient
from http_app import app as victim_app

authed = TestClient(auth_app)
victim = TestClient(victim_app)

HQ = {"X-API-Key": "test_hq_key"}
RESCUE = {"X-API-Key": "test_rescue_key"}


def _cfg(version, label="I am trapped in a flooded house"):
    return {
        "version": version,
        "mission_name": "Flood 2026",
        "disaster_type": "flood",
        "headline": "Tap what you need.",
        "situations": [
            {"id": "trapped", "label": label, "urgent": True},
            {"id": "boat", "label": "I need a boat", "urgent": False},
        ],
    }


def _reset():
    import os
    try:
        os.remove(mission_config._path())
    except OSError:
        pass


def test_a_node_never_pushed_to_serves_stock():
    _reset()
    cfg = mission_config.load()
    assert cfg["source"] == "stock"
    assert cfg["version"] == 0
    assert cfg["situations"], "stock must never be empty, that would break the portal"


def test_health_reports_the_version_so_rollout_is_visible():
    _reset()
    summary = authed.get("/health").json()["mission_config"]
    assert summary["source"] == "stock" and summary["version"] == 0

    assert authed.post("/mission-config", json=_cfg(1), headers=HQ).status_code == 200
    summary = authed.get("/health").json()["mission_config"]
    assert summary["version"] == 1
    assert summary["source"] == "pushed"
    assert summary["mission_name"] == "Flood 2026"


def test_push_changes_what_victims_actually_see():
    _reset()
    assert "I need a boat" not in victim.get("/").text
    authed.post("/mission-config", json=_cfg(1), headers=HQ)
    page = victim.get("/").text
    assert "I need a boat" in page
    assert "Tap what you need." in page


def test_versions_only_move_forward():
    """A stale GCC replaying an old config must not downgrade a node that
    another operator already updated."""
    _reset()
    assert authed.post("/mission-config", json=_cfg(5), headers=HQ).status_code == 200
    for stale in (1, 4, 5):
        r = authed.post("/mission-config", json=_cfg(stale), headers=HQ)
        assert r.status_code == 400, f"version {stale} should have been rejected"
        assert "newer" in r.json()["detail"]
    assert authed.get("/health").json()["mission_config"]["version"] == 5
    assert authed.post("/mission-config", json=_cfg(6), headers=HQ).status_code == 200


def test_only_hq_can_change_what_victims_are_shown():
    _reset()
    assert authed.post("/mission-config", json=_cfg(1)).status_code in {401, 403}
    assert authed.post("/mission-config", json=_cfg(1), headers=RESCUE).status_code == 403


def test_malformed_pushes_are_rejected_not_half_applied():
    _reset()
    authed.post("/mission-config", json=_cfg(1), headers=HQ)
    bad = [
        {"version": 2, "situations": []},
        {"version": 2, "situations": [{"id": "a", "label": ""}]},
        {"version": 2, "situations": [{"id": "dup", "label": "x"},
                                      {"id": "dup", "label": "y"}]},
        {"version": 0, "situations": [{"id": "a", "label": "x"}]},
    ]
    for body in bad:
        assert authed.post("/mission-config", json=body,
                           headers=HQ).status_code in {400, 422}
    # still on the last good version, not wedged or partly written
    assert authed.get("/health").json()["mission_config"]["version"] == 1


def test_corrupt_config_falls_back_to_stock_rather_than_breaking_the_portal():
    """A half-written file must not take the victim portal down: these
    nodes lose power for a living."""
    _reset()
    with open(mission_config._path(), "w", encoding="utf-8") as f:
        f.write("{not json at all")
    assert mission_config.load()["source"] == "stock"
    assert victim.get("/").status_code == 200
    _reset()
