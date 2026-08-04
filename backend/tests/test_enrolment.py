"""
Carrying a credential to a node by hand (field backlog #17).

Credentials are issued by the GCC onto whichever node it is joined to, and
reach other nodes by DTN sync. If the mesh is partitioned, or a rescuer
walks to a drone that has not met the issuing one, they cannot log in at
all. In a delay-tolerant system the PERSON is a viable carrier, so the
signed record travels with them as a QR code.

These tests are mostly about why that is safe without a session, since
accepting an unauthenticated write to the personnel table deserves
scrutiny.

Run with: .venv/bin/pytest tests/test_enrolment.py -q
"""

import base64
import json

import models
from api import app as auth_app
from fastapi.testclient import TestClient

authed = TestClient(auth_app)
HQ = {"X-API-Key": "test_hq_key"}


def _issue(name="Carried Rescuer"):
    r = authed.post("/personnel", json={"name": name, "role": "RESCUE_TEAM"},
                    headers=HQ)
    assert r.status_code == 200, r.text
    return r.json()


def _forget(personnel_id):
    """Simulate a node that has never met the issuing one."""
    conn = models.get_conn()
    conn.execute("DELETE FROM personnel WHERE personnel_id = ?", (personnel_id,))
    conn.commit()
    conn.close()


def test_issuing_returns_a_carryable_credential():
    issued = _issue()
    assert issued["enrolment"], "the GCC needs something to put in a QR code"
    assert issued["pin"]


def test_the_enrolment_blob_never_contains_the_pin():
    """The enrolment blob admits a record to a node and nothing more, so it
    must not be usable to authenticate as that person."""
    issued = _issue()
    decoded = json.loads(base64.urlsafe_b64decode(issued["enrolment"]))
    assert issued["pin"] not in json.dumps(decoded)
    assert decoded["pin_hash"]
    assert "pin" not in decoded


def test_the_signin_code_DOES_carry_the_pin_and_that_is_deliberate():
    """Scan-only sign-in was chosen over scan-then-type (CHANGES.md item
    41). It is defensible because credentials are scoped to a mission, so a
    stolen code dies with the mission rather than lasting indefinitely.
    Pinned by a test so the tradeoff cannot be forgotten or reversed by
    accident."""
    issued = _issue()
    decoded = json.loads(base64.urlsafe_b64decode(issued["signin_code"]))
    assert decoded["p"] == issued["pin"]
    assert decoded["i"] == issued["personnel_id"]
    assert decoded["e"] == issued["enrolment"]


def test_a_rescuer_can_enrol_on_a_node_that_never_saw_them():
    issued = _issue()
    _forget(issued["personnel_id"])
    assert models.get_personnel_by_id(issued["personnel_id"]) is None

    r = authed.post("/enrol", json={"enrolment": issued["enrolment"]})
    assert r.status_code == 200, r.text
    assert r.json()["outcome"] == "inserted"

    # And can then actually log in, which is the whole point.
    login = authed.post("/auth/login", json={
        "personnel_id": issued["personnel_id"], "pin": issued["pin"]})
    assert login.status_code == 200, login.text


def test_enrolment_needs_no_session_but_does_need_a_valid_signature():
    """The signature is the authority, not the transport. A tampered record
    must be refused exactly as it would be arriving over the radio."""
    issued = _issue()
    _forget(issued["personnel_id"])
    record = json.loads(base64.urlsafe_b64decode(issued["enrolment"]))
    record["role"] = "HQ"  # privilege escalation attempt
    tampered = base64.urlsafe_b64encode(
        json.dumps(record).encode()).decode()

    r = authed.post("/enrol", json={"enrolment": tampered})
    assert r.status_code == 400
    assert models.get_personnel_by_id(issued["personnel_id"]) is None


def test_a_revoked_person_cannot_re_enrol_with_an_old_code():
    """The obvious attack: keep the QR, get revoked, walk to another drone.
    Blocked by the same conflict rule that protects sync."""
    issued = _issue()
    authed.post("/enrol", json={"enrolment": issued["enrolment"]})
    models.revoke_personnel(issued["personnel_id"])

    r = authed.post("/enrol", json={"enrolment": issued["enrolment"]})
    assert r.status_code == 200
    assert r.json()["outcome"] == "kept", "revocation must win"
    rec = models.get_personnel_by_id(issued["personnel_id"])
    assert rec["status"] == "REVOKED"

    login = authed.post("/auth/login", json={
        "personnel_id": issued["personnel_id"], "pin": issued["pin"]})
    assert login.status_code != 200


def test_garbage_is_rejected_cleanly():
    for junk in ["", "not-base64!!", base64.urlsafe_b64encode(b"[]").decode(),
                 base64.urlsafe_b64encode(b'{"no":"id"}').decode()]:
        r = authed.post("/enrol", json={"enrolment": junk})
        assert r.status_code in {400, 422}, junk
