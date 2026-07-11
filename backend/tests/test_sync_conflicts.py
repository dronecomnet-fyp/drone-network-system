"""
Sync ingest conflict rules (file 02 task 2.3). Peer records are simulated
by building signed record dicts directly: the fleet shares K_MSG, so a
record signed here is indistinguishable from one signed on another node.
"""

import uuid

import models
import sync_engine


def _make_peer_message(content, status="NEW", claimed_by="", claimed_at="",
                       node_id="DRONE_P", local_ts=None):
    record = {
        "msg_id": str(uuid.uuid4()),
        "content": content,
        "user_lat": 6.9,
        "user_lon": 79.8,
        "node_lat": None,
        "node_lon": None,
        "timestamp": models.iso_now(),
        "time_source": "gps",
        "node_id": node_id,
        "victim_device_id": "",
        "status": status,
        "claimed_by": claimed_by,
        "claimed_at": claimed_at,
        "local_ts": local_ts or models.iso_now(),
    }
    record["signature"] = models.sign_record("messages", record)
    return record


def test_new_message_inserted_with_synced_from():
    rec = _make_peer_message("from peer P")
    assert sync_engine.ingest_message(rec, "DRONE_P") == "inserted"
    stored = models.get_message_by_id(rec["msg_id"])
    assert stored["synced_from"] == "DRONE_P"
    assert stored["status"] == "NEW"
    # idempotent re-ingest
    assert sync_engine.ingest_message(rec, "DRONE_P") == "kept"


def test_tampered_message_rejected():
    rec = _make_peer_message("original")
    rec["content"] = "forged plea"
    assert sync_engine.ingest_message(rec, "DRONE_P") == "rejected"
    assert models.get_message_by_id(rec["msg_id"]) is None


def test_claimed_beats_new():
    rec = _make_peer_message("claim me")
    assert sync_engine.ingest_message(rec, "DRONE_P") == "inserted"
    claimed = dict(rec)
    claimed.update(status="CLAIMED", claimed_by="R-055", claimed_at=models.iso_now())
    assert sync_engine.ingest_message(claimed, "DRONE_P") == "updated"
    stored = models.get_message_by_id(rec["msg_id"])
    assert stored["status"] == "CLAIMED" and stored["claimed_by"] == "R-055"
    # a later NEW copy of the same message cannot un-claim it
    assert sync_engine.ingest_message(rec, "DRONE_P") == "kept"
    assert models.get_message_by_id(rec["msg_id"])["status"] == "CLAIMED"


def test_double_claim_earlier_wins():
    rec = _make_peer_message("double claimed")
    assert sync_engine.ingest_message(rec, "DRONE_P") == "inserted"
    models.claim_message(rec["msg_id"], "R-LOCAL")
    local = models.get_message_by_id(rec["msg_id"])

    # peer claim EARLIER than ours: peer wins
    earlier = dict(rec)
    earlier.update(status="CLAIMED", claimed_by="R-EARLY",
                   claimed_at="2020-01-01T00:00:00.000000Z")
    assert sync_engine.ingest_message(earlier, "DRONE_P") == "updated"
    stored = models.get_message_by_id(rec["msg_id"])
    assert stored["claimed_by"] == "R-EARLY"

    # peer claim LATER than the current one: kept
    later = dict(rec)
    later.update(status="CLAIMED", claimed_by="R-LATE",
                 claimed_at="2030-01-01T00:00:00.000000Z")
    assert sync_engine.ingest_message(later, "DRONE_P") == "kept"
    assert models.get_message_by_id(rec["msg_id"])["claimed_by"] == "R-EARLY"


def _make_peer_personnel(status="ACTIVE", updated_at=None, personnel_id=None):
    record = {
        "personnel_id": personnel_id or f"R-{uuid.uuid4().hex[:6]}",
        "name": "Peer Person",
        "role": "RESCUE_TEAM",
        "pin_salt": "aa" * 16,
        "pin_hash": "bb" * 32,
        "pin_algo": "pbkdf2_sha256",
        "pin_iterations": 210000,
        "issued_at": "2026-07-11T00:00:00.000000Z",
        "expires_at": "",
        "status": status,
        "updated_at": updated_at or models.iso_now(),
        "local_ts": models.iso_now(),
    }
    record["signature"] = models.sign_record("personnel", record)
    return record


def test_personnel_revoked_beats_active():
    rec = _make_peer_personnel(status="ACTIVE", updated_at="2026-07-11T10:00:00.000000Z")
    assert sync_engine.ingest_personnel(rec, "DRONE_P") == "inserted"

    revoked = _make_peer_personnel(status="REVOKED",
                                   updated_at="2026-07-11T11:00:00.000000Z",
                                   personnel_id=rec["personnel_id"])
    assert sync_engine.ingest_personnel(revoked, "DRONE_P") == "updated"
    assert models.get_personnel_by_id(rec["personnel_id"])["status"] == "REVOKED"

    # a NEWER ACTIVE copy still loses to REVOKED
    reactivated = _make_peer_personnel(status="ACTIVE",
                                       updated_at="2026-07-11T12:00:00.000000Z",
                                       personnel_id=rec["personnel_id"])
    assert sync_engine.ingest_personnel(reactivated, "DRONE_P") == "kept"
    assert models.get_personnel_by_id(rec["personnel_id"])["status"] == "REVOKED"


def test_personnel_newest_updated_at_wins():
    rec = _make_peer_personnel(updated_at="2026-07-11T10:00:00.000000Z")
    assert sync_engine.ingest_personnel(rec, "DRONE_P") == "inserted"
    older = _make_peer_personnel(updated_at="2026-07-11T09:00:00.000000Z",
                                 personnel_id=rec["personnel_id"])
    assert sync_engine.ingest_personnel(older, "DRONE_P") == "kept"
    newer = _make_peer_personnel(updated_at="2026-07-11T11:00:00.000000Z",
                                 personnel_id=rec["personnel_id"])
    assert sync_engine.ingest_personnel(newer, "DRONE_P") == "updated"


def test_personnel_tampered_rejected():
    rec = _make_peer_personnel()
    rec["role"] = "HQ"  # privilege escalation attempt breaks the signature
    assert sync_engine.ingest_personnel(rec, "DRONE_P") == "rejected"


def test_announcement_append_only():
    record = {
        "id": str(uuid.uuid4()),
        "title": "Peer announcement",
        "body": "Body",
        "priority": "NORMAL",
        "created_by": "H-001",
        "created_at": models.iso_now(),
        "local_ts": models.iso_now(),
    }
    record["signature"] = models.sign_record("announcements", record)
    assert sync_engine.ingest_announcement(record, "DRONE_P") == "inserted"
    assert sync_engine.ingest_announcement(record, "DRONE_P") == "kept"
    tampered = dict(record)
    tampered["body"] = "changed"
    tampered["id"] = str(uuid.uuid4())
    assert sync_engine.ingest_announcement(tampered, "DRONE_P") == "rejected"


def test_beacon_replay_via_daemon_parser():
    import sync_daemon
    data = sync_daemon.build_beacon()
    # our own beacon is ignored
    assert sync_daemon.parse_and_accept_beacon(data, "10.99.0.9") is False
    # a peer beacon is accepted once, rejected on replay
    import json
    import crypto_keys
    beacon = json.loads(data)
    beacon["node_id"] = "DRONE_R"
    counts_json = json.dumps(beacon["counts"], sort_keys=True, separators=(",", ":"))
    payload = f"DRONE_R|{beacon['api_port']}|{beacon['ts']}|{beacon['counter']}|{counts_json}"
    beacon["sig"] = crypto_keys.hmac_hex(crypto_keys.K_SYNC, payload)
    wire = json.dumps(beacon).encode()
    assert sync_daemon.parse_and_accept_beacon(wire, "10.99.0.9") is True
    assert sync_daemon.parse_and_accept_beacon(wire, "10.99.0.9") is False  # replay
    # bad signature rejected
    beacon["sig"] = "0" * 64
    assert sync_daemon.parse_and_accept_beacon(json.dumps(beacon).encode(), "10.99.0.9") is False
