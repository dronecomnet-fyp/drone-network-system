"""
Credentials belong to a mission (field backlog, 2026-08-05).

Starting a new mission retires every credential from the old one at once,
with no need to revoke people individually or wait for those revocations to
reach every node. That also bounds what a stolen enrolment QR is worth,
which is what makes scan-only sign-in defensible.

Both blanks are permissive, and the tests pin that: a node with no active
mission accepts anyone (a missed push must not lock rescuers out), and a
credential with no mission is not retired retroactively.

Run with: .venv/bin/pytest tests/test_mission_scoped_creds.py -q
"""

import mission_config
import models
from api import app as auth_app
from fastapi.testclient import TestClient

authed = TestClient(auth_app)
HQ = {"X-API-Key": "test_hq_key"}


def _activate(mission_id):
    import os
    if not mission_id:
        try:
            os.remove(mission_config._path())
        except OSError:
            pass
        return
    mission_config.save({
        "mission_id": mission_id,
        "mission_name": mission_id,
        "updated_at": f"2026-08-05T10:00:00.{abs(hash(mission_id)) % 1000000:06d}Z",
        "situations": [{"id": "a", "label": "Need help", "urgent": True}],
    }, force=True)


def _issue(name="Scoped Rescuer"):
    r = authed.post("/personnel", json={"name": name, "role": "RESCUE_TEAM"},
                    headers=HQ)
    assert r.status_code == 200, r.text
    return r.json()


def _login(issued):
    return authed.post("/auth/login", json={
        "personnel_id": issued["personnel_id"], "pin": issued["pin"]})


def test_a_credential_works_during_its_own_mission():
    _activate("flood-2026-08")
    issued = _issue()
    assert _login(issued).status_code == 200


def test_starting_a_new_mission_retires_old_credentials():
    """The whole point: one action retires everyone, with no per-person
    revocation and nothing that has to sync first."""
    _activate("flood-2026-08")
    issued = _issue()
    assert _login(issued).status_code == 200

    _activate("landslide-2026-09")
    r = _login(issued)
    assert r.status_code == 401
    assert "different mission" in r.json()["detail"]


def test_credentials_issued_for_the_new_mission_work():
    _activate("landslide-2026-09")
    issued = _issue("New Mission Rescuer")
    assert _login(issued).status_code == 200


def test_a_node_with_no_active_mission_accepts_anyone():
    """A node nobody pushed a mission to must still let rescuers work.
    Turning a missed push into a lockout would be worse than useless."""
    _activate("flood-2026-08")
    issued = _issue()
    _activate(None)
    assert _login(issued).status_code == 200


def test_a_credential_with_no_mission_is_not_retired_retroactively():
    """Records issued before this feature existed must keep working."""
    _activate(None)
    issued = _issue("Legacy Rescuer")
    rec = models.get_personnel_by_id(issued["personnel_id"])
    assert (rec["mission_id"] or "") == ""

    _activate("flood-2026-08")
    assert _login(issued).status_code == 200
    _activate(None)


def test_mission_id_is_signed_so_it_cannot_be_edited_in_transit():
    """If mission_id were unsigned, anyone relaying a record could strip the
    scoping and resurrect a retired credential."""
    _activate("flood-2026-08")
    issued = _issue("Signed Scope")
    rec = dict(models.get_personnel_by_id(issued["personnel_id"]))
    assert models.verify_record("personnel", rec)

    rec["mission_id"] = "landslide-2026-09"
    assert not models.verify_record("personnel", rec), (
        "changing the mission on a signed record must invalidate it")
    _activate(None)
