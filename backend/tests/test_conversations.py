"""
Victim conversations: replies, delivery state, and the device-scoped read
(CHANGES.md item 37).

This is the feature that REVERSES file 09's "no read endpoints on the open
victim plane" rule, so the tests are as much about what must NOT be
reachable as about what must.

Run with: .venv/bin/pytest tests/test_conversations.py -q
"""

import models
from api import app as auth_app
from fastapi.testclient import TestClient
from http_app import app as victim_app

authed = TestClient(auth_app)
victim = TestClient(victim_app)

HQ = {"X-API-Key": "test_hq_key"}
RESCUE = {"X-API-Key": "test_rescue_key"}

DEV_A = "11111111-1111-4111-8111-111111111111"
DEV_B = "22222222-2222-4222-8222-222222222222"


def _send(device_id, content="I am trapped by water"):
    r = victim.post("/message", json={
        "content": content, "victim_device_id": device_id,
        "user_lat": 6.92, "user_lon": 79.86,
    })
    assert r.status_code == 200, r.text
    return r.json()["msg_id"]


def test_victim_reads_back_their_own_message():
    msg_id = _send(DEV_A)
    convo = victim.get(f"/my-conversation/{DEV_A}").json()
    ids = [m["msg_id"] for m in convo["messages"]]
    assert msg_id in ids
    # NEW is the "on the drone, nobody has seen it" tick state.
    sent = next(m for m in convo["messages"] if m["msg_id"] == msg_id)
    assert sent["status"] == "NEW"
    assert convo["replies"] == []


def test_a_rescuer_reply_reaches_the_victim_thread():
    msg_id = _send(DEV_A, "I need a boat")
    r = authed.post(f"/messages/{msg_id}/reply",
                    json={"msg_id": msg_id, "body": "Boat on the way, stay put"},
                    headers=RESCUE)
    assert r.status_code == 200, r.text

    convo = victim.get(f"/my-conversation/{DEV_A}").json()
    bodies = [x["body"] for x in convo["replies"]]
    assert "Boat on the way, stay put" in bodies


def test_claiming_a_message_is_the_seen_tick():
    """The victim's double tick is CLAIMED: a rescuer has actually picked it
    up. It must never be implied before that happens."""
    msg_id = _send(DEV_A, "Roof, two people")
    before = victim.get(f"/my-conversation/{DEV_A}").json()
    assert all(m["status"] == "NEW" for m in before["messages"]
               if m["msg_id"] == msg_id)

    assert authed.post(f"/messages/{msg_id}/claim",
                       headers=RESCUE).status_code == 200
    after = victim.get(f"/my-conversation/{DEV_A}").json()
    claimed = next(m for m in after["messages"] if m["msg_id"] == msg_id)
    assert claimed["status"] == "CLAIMED"


def test_one_device_cannot_read_another_device_thread():
    """The core property that lets the open plane have a read at all."""
    _send(DEV_A, "Device A private situation")
    _send(DEV_B, "Device B private situation")

    a = victim.get(f"/my-conversation/{DEV_A}").json()
    a_text = " ".join(m["content"] for m in a["messages"])
    assert "Device A" in a_text
    assert "Device B" not in a_text, "threads must not leak across devices"


def test_there_is_no_way_to_list_or_enumerate_conversations():
    _send(DEV_A)
    # No listing endpoint: the catch-all serves the HTML form, not data.
    for path in ("/my-conversation/", "/my-conversation", "/conversations",
                 "/my-conversations"):
        r = victim.get(path)
        assert "msg_id" not in r.text or r.headers["content-type"].startswith(
            "text/html"), f"{path} must not return conversation data"


def test_an_unknown_device_looks_exactly_like_a_silent_one():
    """No oracle: probing a random id must not reveal whether it exists."""
    unknown = victim.get("/my-conversation/00000000-0000-4000-8000-000000000000")
    assert unknown.status_code == 200
    assert unknown.json() == {"messages": [], "replies": []}


def test_replies_need_authentication():
    msg_id = _send(DEV_A)
    body = {"msg_id": msg_id, "body": "unauthenticated reply"}
    # 405 on the victim plane: the route simply is not there, which is
    # the point. Replying is an authenticated-plane action only.
    assert victim.post(f"/messages/{msg_id}/reply",
                       json=body).status_code in {404, 405}
    assert authed.post(f"/messages/{msg_id}/reply", json=body).status_code in {401, 403}


def test_reply_to_an_unknown_message_is_rejected():
    r = authed.post("/messages/does-not-exist/reply",
                    json={"msg_id": "does-not-exist", "body": "hello"},
                    headers=RESCUE)
    assert r.status_code == 404


def test_replies_are_signed_so_they_survive_the_mesh():
    msg_id = _send(DEV_A)
    authed.post(f"/messages/{msg_id}/reply",
                json={"msg_id": msg_id, "body": "Signed reply"}, headers=HQ)
    conn = models.get_conn()
    row = conn.execute(
        "SELECT * FROM message_replies WHERE body = ?", ("Signed reply",)
    ).fetchone()
    conn.close()
    assert row is not None and row["signature"]
    assert models.verify_record("message_replies", dict(row))


def test_a_tampered_reply_fails_verification():
    msg_id = _send(DEV_A)
    authed.post(f"/messages/{msg_id}/reply",
                json={"msg_id": msg_id, "body": "Original"}, headers=HQ)
    conn = models.get_conn()
    row = dict(conn.execute(
        "SELECT * FROM message_replies WHERE body = ?", ("Original",)
    ).fetchone())
    conn.close()
    row["body"] = "Move to the river immediately"
    assert not models.verify_record("message_replies", row), (
        "an altered reply must not verify, or a captured node could put "
        "dangerous instructions in a rescuer's mouth"
    )
