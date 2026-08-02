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


def _cfg(at="2026-08-02T10:00:00.000000Z",
         label="I am trapped in a flooded house"):
    return {
        "updated_at": at,
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
    assert cfg["config_id"] == "stock"
    assert cfg["situations"], "stock must never be empty, that would break the portal"


def test_health_reports_the_config_so_rollout_is_visible():
    _reset()
    summary = authed.get("/health").json()["mission_config"]
    assert summary["source"] == "stock"

    assert authed.post("/mission-config", json=_cfg(), headers=HQ).status_code == 200
    summary = authed.get("/health").json()["mission_config"]
    assert summary["source"] == "pushed"
    assert summary["mission_name"] == "Flood 2026"
    assert len(summary["config_id"]) == 12


def test_the_same_options_always_fingerprint_the_same():
    """The GCC compares ids to decide whether a node already matches, so an
    unstable hash would report every node as different forever."""
    a = mission_config.content_id(_cfg())
    b = mission_config.content_id(_cfg(at="2027-01-01T00:00:00.000000Z"))
    assert a == b, "timestamp must not affect the fingerprint"
    c = mission_config.content_id(_cfg(label="Something else"))
    assert c != a, "changing what victims read must change the fingerprint"


def test_push_changes_what_victims_actually_see():
    _reset()
    assert "I need a boat" not in victim.get("/").text
    authed.post("/mission-config", json=_cfg(), headers=HQ)
    page = victim.get("/").text
    assert "I need a boat" in page
    assert "Tap what you need." in page


def test_an_older_push_is_refused_but_can_be_forced():
    """A second laptop carrying a stale mission file must not silently undo
    someone else's newer push. The operator can still override deliberately,
    which is the escape hatch for a wrong laptop clock."""
    _reset()
    newer = "2026-08-02T12:00:00.000000Z"
    older = "2026-08-02T09:00:00.000000Z"
    assert authed.post("/mission-config", json=_cfg(at=newer),
                       headers=HQ).status_code == 200

    r = authed.post("/mission-config", json=_cfg(at=older, label="Stale"),
                    headers=HQ)
    assert r.status_code == 400
    assert "older" in r.json()["detail"]
    assert "Stale" not in victim.get("/").text

    forced = _cfg(at=older, label="Stale")
    forced["force"] = True
    assert authed.post("/mission-config", json=forced,
                       headers=HQ).status_code == 200
    assert "Stale" in victim.get("/").text


def test_pushing_the_same_options_twice_is_harmless():
    """Re-pushing must not error or change the fingerprint: the operator
    should be able to push again without thinking about it."""
    _reset()
    r1 = authed.post("/mission-config", json=_cfg(at="2026-08-02T10:00:00.000000Z"),
                     headers=HQ)
    r2 = authed.post("/mission-config", json=_cfg(at="2026-08-02T11:00:00.000000Z"),
                     headers=HQ)
    assert r1.status_code == 200 and r2.status_code == 200
    assert r1.json()["config_id"] == r2.json()["config_id"]


def test_only_hq_can_change_what_victims_are_shown():
    _reset()
    assert authed.post("/mission-config", json=_cfg()).status_code in {401, 403}
    assert authed.post("/mission-config", json=_cfg(), headers=RESCUE).status_code == 403


def test_malformed_pushes_are_rejected_not_half_applied():
    _reset()
    authed.post("/mission-config", json=_cfg(), headers=HQ)
    good_id = authed.get("/health").json()["mission_config"]["config_id"]
    bad = [
        {"situations": []},
        {"situations": [{"id": "a", "label": ""}]},
        {"situations": [{"id": "dup", "label": "x"}, {"id": "dup", "label": "y"}]},
    ]
    for body in bad:
        assert authed.post("/mission-config", json=body,
                           headers=HQ).status_code in {400, 422}
    # still serving the last good config, not wedged or partly written
    assert authed.get("/health").json()["mission_config"]["config_id"] == good_id


def test_corrupt_config_falls_back_to_stock_rather_than_breaking_the_portal():
    """A half-written file must not take the victim portal down: these
    nodes lose power for a living."""
    _reset()
    with open(mission_config._path(), "w", encoding="utf-8") as f:
        f.write("{not json at all")
    assert mission_config.load()["source"] == "stock"
    assert victim.get("/").status_code == 200
    _reset()
