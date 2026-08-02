"""
sync_engine.py: pull-sync client and record ingest with per-table conflict
rules (file 02 task 2.3). Rewritten from Phase 1: the pull pattern and the
signature-verification-per-record loop are kept, extended from messages
alone to ALL replicated tables (fixing the Phase 1 gap where gs_messages
never left the node they were filed on).

Conflict rules (file 02):
  messages       CLAIMED beats NEW; if both CLAIMED, the EARLIER claimed_at
                 wins and its claimed_by is retained.
  personnel      REVOKED beats ACTIVE; otherwise newest (signed, origin)
                 updated_at wins.
  announcements, gs_messages, checkins: append-only by primary key.

Every ingested row is stamped with a fresh LOCAL local_ts so it propagates
onward to peers that sync from us (DTN store-and-forward). The per-peer
cursor advances in the PEER's local_ts space (see models.py header).
"""

import json

import requests

import audit
import config
import crypto_keys
import models

audit_logger = audit.get_audit_logger()

# API path per replicated table (hyphenated on the wire, file 02).
SYNC_PATHS = {
    "messages": "messages",
    "personnel": "personnel",
    "announcements": "announcements",
    "gs_messages": "gs-messages",
    "checkins": "checkins",
    "personnel_locations": "personnel-locations",
    "message_replies": "message-replies",
}


# ---------------------------------------------------------------------------
# Ingest (used by the sync daemon after pulling from a peer)
# ---------------------------------------------------------------------------

def ingest_message(record: dict, peer_node_id: str) -> str:
    """Returns one of: inserted, updated, kept, rejected."""
    if not models.verify_record("messages", record):
        return "rejected"
    existing = models.get_message_by_id(record["msg_id"])
    now = models.iso_now()
    conn = models.get_conn()
    try:
        if existing is None:
            conn.execute("""
                INSERT INTO messages (
                    msg_id, content, user_lat, user_lon, node_lat, node_lon,
                    timestamp, time_source, node_id, status, claimed_by,
                    claimed_at, synced_from, signature, is_encrypted,
                    encryption_alg, encryption_kid, victim_device_id, local_ts
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                record["msg_id"], record.get("content"), record.get("user_lat"),
                record.get("user_lon"), record.get("node_lat"), record.get("node_lon"),
                record.get("timestamp"), record.get("time_source", "relative"),
                record.get("node_id"), record.get("status", "NEW"),
                record.get("claimed_by", ""), record.get("claimed_at", ""),
                peer_node_id, record.get("signature"),
                1 if record.get("is_encrypted") else 0,
                record.get("encryption_alg", ""), record.get("encryption_kid", ""),
                record.get("victim_device_id", ""), now,
            ))
            conn.commit()
            return "inserted"

        peer_status = record.get("status", "NEW")
        if existing["status"] == "CLAIMED" and peer_status == "CLAIMED":
            # Both claimed: earlier claim wins, keep its claimed_by.
            peer_claimed_at = record.get("claimed_at") or ""
            if peer_claimed_at and (not existing["claimed_at"]
                                    or peer_claimed_at < existing["claimed_at"]):
                conn.execute(
                    """UPDATE messages SET claimed_by = ?, claimed_at = ?, local_ts = ?
                       WHERE msg_id = ?""",
                    (record.get("claimed_by", ""), peer_claimed_at, now, record["msg_id"]),
                )
                conn.commit()
                return "updated"
            return "kept"
        if peer_status == "CLAIMED" and existing["status"] != "CLAIMED":
            conn.execute(
                """UPDATE messages SET status = 'CLAIMED', claimed_by = ?,
                   claimed_at = ?, local_ts = ? WHERE msg_id = ?""",
                (record.get("claimed_by", ""), record.get("claimed_at", ""),
                 now, record["msg_id"]),
            )
            conn.commit()
            return "updated"
        return "kept"
    finally:
        conn.close()


def ingest_personnel(record: dict, peer_node_id: str) -> str:
    if not models.verify_record("personnel", record):
        return "rejected"
    existing = models.get_personnel_by_id(record["personnel_id"])
    if existing is None:
        models.write_personnel_record(record)
        return "inserted"
    if existing["status"] == "REVOKED" and record.get("status") != "REVOKED":
        return "kept"
    if record.get("status") == "REVOKED" and existing["status"] != "REVOKED":
        models.write_personnel_record(record)
        return "updated"
    if (record.get("updated_at") or "") > (existing["updated_at"] or ""):
        models.write_personnel_record(record)
        return "updated"
    return "kept"


def _ingest_append_only(table: str, record: dict, columns: list) -> str:
    if not models.verify_record(table, record):
        return "rejected"
    pk = models.REPLICATED_TABLES[table]
    now = models.iso_now()
    conn = models.get_conn()
    try:
        exists = conn.execute(
            f"SELECT 1 FROM {table} WHERE {pk} = ?", (record[pk],)
        ).fetchone()
        if exists:
            return "kept"
        col_list = ", ".join(columns) + ", local_ts"
        placeholders = ", ".join("?" for _ in columns) + ", ?"
        values = [record.get(c) for c in columns] + [now]
        conn.execute(f"INSERT INTO {table} ({col_list}) VALUES ({placeholders})", values)
        conn.commit()
        return "inserted"
    finally:
        conn.close()


def ingest_announcement(record, peer_node_id):
    return _ingest_append_only(
        "announcements", record,
        ["id", "title", "body", "priority", "created_by", "created_at", "signature"],
    )


def ingest_gs_message(record, peer_node_id):
    return _ingest_append_only(
        "gs_messages", record,
        ["id", "content", "sender", "timestamp", "node_id", "location_lat",
         "location_lon", "location_accuracy", "location_timestamp", "signature"],
    )


def ingest_checkin(record, peer_node_id):
    return _ingest_append_only(
        "checkins", record,
        ["id", "device_id", "lat", "lon", "accuracy", "recorded_at",
         "uploaded_at", "node_id", "sos", "signature"],
    )


def ingest_message_reply(record, peer_node_id):
    # Append-only, like checkins: a reply is an immutable utterance, so
    # there is no conflict to resolve, only a duplicate to ignore.
    return _ingest_append_only(
        "message_replies", record,
        ["id", "msg_id", "victim_device_id", "body", "sender", "sender_role",
         "created_at", "node_id", "signature"],
    )


def ingest_personnel_location(record, peer_node_id):
    # Latest-per-rescuer: newest signed origin updated_at wins (same shape as
    # ingest_personnel, minus the REVOKED override which does not apply).
    if not models.verify_record("personnel_locations", record):
        return "rejected"
    existing = models.get_personnel_location_by_id(record["personnel_id"])
    if existing is None:
        models.write_personnel_location_record(record)
        return "inserted"
    if (record.get("updated_at") or "") > (existing["updated_at"] or ""):
        models.write_personnel_location_record(record)
        return "updated"
    return "kept"


INGEST_FN = {
    "messages": ingest_message,
    "personnel": ingest_personnel,
    "announcements": ingest_announcement,
    "gs_messages": ingest_gs_message,
    "checkins": ingest_checkin,
    "personnel_locations": ingest_personnel_location,
    "message_replies": ingest_message_reply,
}


# ---------------------------------------------------------------------------
# Pull client
# ---------------------------------------------------------------------------

def sync_table_with_peer(peer: dict, table: str) -> dict:
    """Pull one table's delta from one peer and ingest it. Returns a stats
    dict. Raises requests exceptions upward; the caller isolates failures
    per table (file 02 task 2.5 error handling)."""
    peer_ip = peer["ip"]
    peer_node_id = peer["node_id"]
    api_port = peer.get("api_port") or config.API_PORT
    since = models.get_sync_cursor(peer_node_id, table)
    url = f"{config.SYNC_SCHEME}://{peer_ip}:{api_port}/sync/{SYNC_PATHS[table]}"
    verify = config.SYNC_CA_CERT if config.SYNC_VERIFY_TLS else False
    resp = requests.get(
        url,
        params={"since": since},
        headers={"X-Node-Auth": crypto_keys.NODE_AUTH_VALUE},
        verify=verify,
        timeout=10,
    )
    resp.raise_for_status()
    rows = resp.json()
    stats = {"inserted": 0, "updated": 0, "kept": 0, "rejected": 0}
    max_ts = since
    ingest = INGEST_FN[table]
    for record in rows:
        try:
            outcome = ingest(record, peer_node_id)
        except (KeyError, TypeError, ValueError):
            outcome = "rejected"
        stats[outcome] += 1
        if outcome == "rejected":
            audit_logger.warning(
                f"SYNC_REJECT | peer={peer_node_id} | table={table} | "
                f"pk={record.get(models.REPLICATED_TABLES[table], 'UNKNOWN')} | reason=bad_signature"
            )
        row_ts = record.get("local_ts") or ""
        if row_ts > max_ts:
            max_ts = row_ts
    if max_ts != since:
        models.set_sync_cursor(peer_node_id, table, max_ts)
    return stats


def fetch_peer_health(peer: dict) -> bool:
    """Cache one peer's live health (position, battery, GPS fix) locally.

    node_health is deliberately NOT a replicated DTN table: it is live state,
    not a record, and stale health must never travel the mesh pretending to
    be current. So instead of syncing it we FETCH it, straight from the peer
    over the same fleet-CA-pinned HTTPS the table pull uses, and stamp it
    with OUR clock. Whatever we store is therefore "what that node said when
    we last reached it", which is exactly what the GCC renders with an age.

    Two things fall out of this, both wanted:
      - the peers table finally has position and battery to show, instead of
        just a last-seen time
      - a successful fetch is PROOF that peer's Pi is alive, so it clears any
        stale degraded flag left behind by an old LoRa fallback beacon

    A peer running older code has no /health we can parse: the request just
    fails and we skip it, so this is safe on a partially updated fleet.
    """
    peer_ip = peer["ip"]
    peer_node_id = peer["node_id"]
    api_port = peer.get("api_port") or config.API_PORT
    url = f"{config.SYNC_SCHEME}://{peer_ip}:{api_port}/health"
    verify = config.SYNC_CA_CERT if config.SYNC_VERIFY_TLS else False
    try:
        resp = requests.get(url, verify=verify, timeout=10)
        resp.raise_for_status()
        h = resp.json()
    except Exception as e:  # noqa: BLE001
        # Broad ON PURPOSE. This is a nice-to-have cache sitting in front of
        # the DTN sync that the whole system exists for, so NOTHING it can
        # do may prevent messages replicating. A missing CA file raises
        # OSError rather than a RequestException, which is exactly the kind
        # of thing that used to escape a narrower catch and kill the cycle.
        audit_logger.warning(
            f"PEER_HEALTH_FAIL | peer={peer_node_id} | reason={type(e).__name__}"
        )
        return False

    # Trust the identity the peer reports about ITSELF only; never let one
    # peer's /health rewrite a third node's row.
    if h.get("node_id") != peer_node_id:
        audit_logger.warning(
            f"PEER_HEALTH_REJECT | peer={peer_node_id} | reason=node_id_mismatch"
        )
        return False

    try:
        gps = h.get("gps") or {}
        bat = h.get("battery") or {}
        models.save_node_health(
            node_id=peer_node_id,
            lat=gps.get("lat"),
            lon=gps.get("lon"),
            gps_fix=1 if gps.get("fix") else 0,
            bat_a_v=bat.get("a_v"), bat_a_ma=bat.get("a_ma"),
            bat_b_v=bat.get("b_v"), bat_b_ma=bat.get("b_ma"),
            uptime_s=h.get("uptime_s"),
            clock_source=h.get("clock_source", "relative"),
            degraded=0,   # we just spoke to its Pi over HTTP: it is not down
        )
    except Exception as e:  # noqa: BLE001
        # A locked database or an unexpected field type here must not stop
        # messages syncing. Caching health is strictly optional; replicating
        # a victim's plea for help is not.
        audit_logger.warning(
            f"PEER_HEALTH_STORE_FAIL | peer={peer_node_id} | reason={type(e).__name__}"
        )
        return False
    return True


def sync_with_peer(peer: dict) -> bool:
    """Sync every replicated table from one peer, isolating failures per
    table so one bad table does not stop the rest."""
    peer_node_id = peer["node_id"]
    audit_logger.info(f"SYNC_START | peer={peer_node_id} | ip={peer['ip']}")
    # Belt and braces: fetch_peer_health already swallows everything, but it
    # runs BEFORE the table loop, so anything escaping it would abort the
    # whole cycle for every peer and every table. That regression stopped
    # two nodes syncing at all in field testing, so the guard stays even
    # though the callee is also defensive.
    try:
        fetch_peer_health(peer)
    except Exception as e:  # noqa: BLE001
        audit_logger.warning(
            f"PEER_HEALTH_FAIL | peer={peer_node_id} | reason={type(e).__name__}")

    any_fail = False
    for table in models.REPLICATED_TABLES:
        try:
            stats = sync_table_with_peer(peer, table)
            audit_logger.info(
                f"SYNC_OK | peer={peer_node_id} | table={table} | "
                f"imported={stats['inserted']} | updated={stats['updated']} | "
                f"rejected={stats['rejected']}"
            )
        except requests.exceptions.RequestException as e:
            any_fail = True
            audit_logger.warning(
                f"SYNC_FAIL | peer={peer_node_id} | table={table} | reason={type(e).__name__}"
            )
        except (json.JSONDecodeError, ValueError) as e:
            any_fail = True
            audit_logger.warning(
                f"SYNC_FAIL | peer={peer_node_id} | table={table} | reason=bad_response_{type(e).__name__}"
            )
        except Exception as e:  # noqa: BLE001
            # Anything else (a sqlite error mid-ingest, a malformed record
            # type) is isolated to THIS table. Previously it escaped and
            # took every remaining table with it, so one bad row could stop
            # messages replicating entirely.
            any_fail = True
            audit_logger.warning(
                f"SYNC_FAIL | peer={peer_node_id} | table={table} | reason={type(e).__name__}"
            )
    return not any_fail
