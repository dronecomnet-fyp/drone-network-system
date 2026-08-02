"""
Sync must not be stoppable by anything optional (CHANGES.md item 39).

Field failure this pins down: two nodes stopped replicating messages
entirely. The cause was the peer-health cache, a convenience feature added
in front of the sync loop, being able to raise. It ran BEFORE the per-table
loop and outside any guard, so one error there aborted the whole cycle for
every peer and every table. The headline feature of the system was taken
down by a nice-to-have.

The rule these tests enforce: replicating a victim's message is the point
of the product; everything else is optional and must fail quietly.

Run with: .venv/bin/pytest tests/test_sync_resilience.py -q
"""

import models
import sync_engine


def _peer():
    return {"node_id": "DRONE_FAKE", "ip": "10.99.0.99", "api_port": 8443}


def test_health_fetch_never_raises_on_a_dead_peer(monkeypatch):
    """Unreachable peer: normal in DTN, must be a quiet False."""
    assert sync_engine.fetch_peer_health(_peer()) is False


def test_health_fetch_swallows_a_non_request_exception(monkeypatch):
    """A missing CA file raises OSError, NOT a RequestException. That is
    exactly the class of error that escaped the original narrow catch."""
    def boom(*a, **k):
        raise OSError("Could not find a suitable TLS CA certificate bundle")
    monkeypatch.setattr(sync_engine.requests, "get", boom)
    assert sync_engine.fetch_peer_health(_peer()) is False


def test_health_fetch_swallows_a_storage_failure(monkeypatch):
    """The DB write is optional too: a locked database must not stop sync."""
    class FakeResp:
        status_code = 200
        def raise_for_status(self): pass
        def json(self):
            return {"node_id": "DRONE_FAKE", "gps": {}, "battery": {}}

    monkeypatch.setattr(sync_engine.requests, "get", lambda *a, **k: FakeResp())
    def boom(*a, **k):
        raise RuntimeError("database is locked")
    monkeypatch.setattr(sync_engine.models, "save_node_health", boom)
    assert sync_engine.fetch_peer_health(_peer()) is False


def test_messages_still_sync_when_the_health_cache_explodes(monkeypatch):
    """THE regression test. Health fetch blowing up must not stop the
    per-table sync from being attempted."""
    def boom(*a, **k):
        raise RuntimeError("anything at all")
    monkeypatch.setattr(sync_engine, "fetch_peer_health", boom)

    attempted = []
    def fake_table(peer, table):
        attempted.append(table)
        return {"inserted": 0, "updated": 0, "kept": 0, "rejected": 0}
    monkeypatch.setattr(sync_engine, "sync_table_with_peer", fake_table)

    sync_engine.sync_with_peer(_peer())
    assert "messages" in attempted, (
        "the health cache must never be able to stop messages replicating"
    )
    assert set(attempted) == set(models.REPLICATED_TABLES)


def test_one_bad_table_does_not_stop_the_others(monkeypatch):
    """A sqlite error mid-ingest used to escape and take every remaining
    table with it, so a single bad row could halt message replication."""
    attempted = []
    def fake_table(peer, table):
        attempted.append(table)
        if table == "personnel":
            raise RuntimeError("sqlite went wrong on this table only")
        return {"inserted": 0, "updated": 0, "kept": 0, "rejected": 0}
    monkeypatch.setattr(sync_engine, "sync_table_with_peer", fake_table)
    monkeypatch.setattr(sync_engine, "fetch_peer_health", lambda p: True)

    ok = sync_engine.sync_with_peer(_peer())
    assert ok is False, "the failure should still be reported"
    assert set(attempted) == set(models.REPLICATED_TABLES), (
        "every table must still be attempted"
    )
