"""
Every replicated table must be wired up in ALL of its places.

This exists because of a support question that was hard to answer. An
operator following the node update runbook ran the gate command:

    journalctl -u rescue-mesh-sync | grep lora_events

and got nothing back. Blank output has two very different meanings: the
table is not registered in the sync loop, or the node has no peers so the
loop never ran. Only one of those is a code bug, and telling them apart
took a diagnostic session.

Adding a table means touching five separate places. Miss one and the
symptom is silence, which is the worst kind of failure to debug in the
field. These tests make a half-registered table fail here instead.

Run with: .venv/bin/pytest tests/test_sync_wiring.py -q
"""

import models
import sync_engine
from api import app as auth_app


def test_every_replicated_table_has_a_payload_function():
    """Without one, sign_record raises KeyError at the first write."""
    missing = [t for t in models.REPLICATED_TABLES if t not in models._PAYLOAD_FN]
    assert not missing, f"no canonical payload function for: {missing}"


def test_every_replicated_table_has_a_sync_path():
    """Without one, sync_table_with_peer raises KeyError and the whole
    table is skipped with a confusing generic failure."""
    missing = [t for t in models.REPLICATED_TABLES if t not in sync_engine.SYNC_PATHS]
    assert not missing, f"no SYNC_PATHS entry for: {missing}"


def test_every_replicated_table_has_an_ingest_function():
    missing = [t for t in models.REPLICATED_TABLES if t not in sync_engine.INGEST_FN]
    assert not missing, f"no INGEST_FN entry for: {missing}"


def test_every_sync_path_is_actually_served():
    """The peer has to have the endpoint, or the pull 404s. This is the
    one that catches a table registered on the client side only."""
    served = {r.path for r in auth_app.routes if getattr(r, "path", "").startswith("/sync/")}
    missing = [
        f"{table} -> /sync/{path}"
        for table, path in sync_engine.SYNC_PATHS.items()
        if f"/sync/{path}" not in served
    ]
    assert not missing, f"no route serving: {missing}"


def test_no_orphan_sync_paths():
    """A path registered for a table that no longer replicates would sync
    forever against a table nobody writes."""
    orphans = [t for t in sync_engine.SYNC_PATHS if t not in models.REPLICATED_TABLES]
    assert not orphans, f"SYNC_PATHS entries with no replicated table: {orphans}"


def test_every_replicated_table_exists_in_the_database():
    """Registered but never created is another silent-failure shape: the
    sync loop queries a table that is not there."""
    models.init_db()
    conn = models.get_conn()
    names = {r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table'").fetchall()}
    conn.close()
    missing = [t for t in models.REPLICATED_TABLES if t not in names]
    assert not missing, f"registered for sync but no CREATE TABLE: {missing}"


def test_the_current_set_is_what_the_documentation_claims():
    """The report, the handbook and the runbooks all state a count. If a
    table is added without updating them, this is the reminder."""
    assert len(models.REPLICATED_TABLES) == 8, (
        f"{len(models.REPLICATED_TABLES)} replicated tables now. Update "
        "docs/CHANGES.md, documentation/04 and 06, and the report audit, "
        "then change this number."
    )
