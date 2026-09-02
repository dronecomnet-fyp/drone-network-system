"""
models.py: SQLite schema v3 and all data access (file 02 task 2.1).

Schema follows communication_module_design_v3 section 3.4 for the messages
table, plus the Phase 1 security columns, plus the new tables: personnel,
announcements, checkins, node_health, and gs_messages (which gains a
signature column so field reports finally sync, closing the Phase 1 gap).

NO migration from Phase 1 databases: the fleet is rebuilt together (master
plan D1), so init_db() creates v3 fresh. Master plan R6 records this as a
prototype-phase decision; mixed Phase 1 / Phase 2 fleets are incompatible.

Record signing (file 09: KEEP, the single most important control): every
replicated record carries an HMAC-SHA256 signature over a canonical field
order, keyed with K_MSG (purpose-derived, file 09 F2). Receivers verify at
sync ingest and reject records that fail (sync_engine.py).

Implementation columns beyond the design v3 list, each with a reason:
  local_ts     on every replicated table: the delta-sync cursor. Stamped
               with LOCAL time on every local write INCLUDING sync ingest,
               so a record received from A re-syncs onward to C (DTN
               transitive propagation). Never signed: it changes per hop.
               Each puller's cursor lives in the PEER's local_ts space.
  claimed_at   on messages: needed to implement the file 02 conflict rule
               "if both CLAIMED, keep the earlier claim".
personnel.updated_at is DIFFERENT from local_ts: it is the signed,
origin-stamped version field used for conflict resolution ("newest
updated_at wins"), so it must travel unchanged and cannot double as the
per-hop cursor. Timestamps are ISO 8601 UTC strings with microseconds
(sortable; the cursor comparison needs sub-second resolution).
"""
from __future__ import annotations

import hashlib
import hmac as hmac_mod
import os
import secrets
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone
from typing import Optional

import aux_state
import config
import crypto_keys

DB_FILE = config.DB_FILE

# Tables that replicate over DTN sync, and their primary key column.
REPLICATED_TABLES = {
    "messages": "msg_id",
    "personnel": "personnel_id",
    "announcements": "id",
    "gs_messages": "id",
    "checkins": "id",
    "personnel_locations": "personnel_id",
    "message_replies": "id",
    "lora_events": "id",
    "media_attachments": "id",
}


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def iso_in_hours(hours: float) -> str:
    return (datetime.now(timezone.utc) + timedelta(hours=hours)).strftime(
        "%Y-%m-%dT%H:%M:%S.%fZ"
    )


def get_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_FILE, timeout=5)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA busy_timeout=5000;")
    return conn


# ---------------------------------------------------------------------------
# Canonical signing (file 02 task 2.1: canonical field order per table).
# None becomes the empty string; everything else is str(). Floats use the
# Python shortest-round-trip repr, which survives a JSON round trip between
# CPython nodes unchanged (the whole fleet runs CPython).
#
# Mutable workflow state (message status, claimed_by) is NOT signed, exactly
# as Phase 1 signed only identity fields: changing claim state requires
# K_SYNC possession (sync plane auth), while record forgery requires K_MSG.
# ---------------------------------------------------------------------------

def _canon(*fields) -> str:
    return "|".join("" if f is None else str(f) for f in fields)


def _message_payload(r: dict) -> str:
    return _canon(
        r.get("msg_id"), r.get("content"), r.get("timestamp"), r.get("time_source"),
        r.get("node_id"), r.get("user_lat"), r.get("user_lon"),
        r.get("node_lat"), r.get("node_lon"), r.get("victim_device_id"),
    )


def _personnel_payload(r: dict) -> str:
    # mission_id is SIGNED: it is what stops a credential from a previous
    # mission being replayed, so it must not be editable in transit.
    # Appended at the end so records signed before it existed still verify
    # (an absent value canonicalises to the empty string either way).
    return _canon(
        r.get("personnel_id"), r.get("name"), r.get("role"),
        r.get("pin_salt"), r.get("pin_hash"), r.get("pin_algo"),
        r.get("pin_iterations"), r.get("issued_at"), r.get("expires_at"),
        r.get("status"), r.get("updated_at"), r.get("mission_id"),
    )


def _announcement_payload(r: dict) -> str:
    return _canon(
        r.get("id"), r.get("title"), r.get("body"), r.get("priority"),
        r.get("created_by"), r.get("created_at"),
    )


def _gs_message_payload(r: dict) -> str:
    return _canon(
        r.get("id"), r.get("content"), r.get("sender"), r.get("timestamp"),
        r.get("node_id"), r.get("location_lat"), r.get("location_lon"),
    )


def _checkin_payload(r: dict) -> str:
    return _canon(
        r.get("id"), r.get("device_id"), r.get("lat"), r.get("lon"),
        r.get("accuracy"), r.get("recorded_at"), r.get("node_id"), r.get("sos"),
    )


def _personnel_location_payload(r: dict) -> str:
    return _canon(
        r.get("personnel_id"), r.get("lat"), r.get("lon"), r.get("accuracy_m"),
        r.get("battery_pct"), r.get("recorded_at"), r.get("node_id"),
        r.get("updated_at"),
    )


def _message_reply_payload(r: dict) -> str:
    return _canon(
        r.get("id"), r.get("msg_id"), r.get("victim_device_id"),
        r.get("body"), r.get("sender"), r.get("sender_role"),
        r.get("created_at"), r.get("node_id"),
    )


def _lora_event_payload(r: dict) -> str:
    return "|".join(str(x) for x in (
        r.get("id"), r.get("kind"), r.get("about_node"), r.get("heard_by"),
        r.get("received_at"), r.get("raw"),
    ))


def _media_attachment_payload(r: dict) -> str:
    return _canon(
        r.get("id"), r.get("parent_table"), r.get("parent_id"),
        r.get("filename"), r.get("mime_type"), r.get("size_bytes"),
        r.get("sha256"), r.get("created_at"), r.get("node_id"),
    )


_PAYLOAD_FN = {
    "messages": _message_payload,
    "personnel": _personnel_payload,
    "announcements": _announcement_payload,
    "gs_messages": _gs_message_payload,
    "checkins": _checkin_payload,
    "personnel_locations": _personnel_location_payload,
    "message_replies": _message_reply_payload,
    "lora_events": _lora_event_payload,
    "media_attachments": _media_attachment_payload,
}


def sign_record(table: str, record: dict) -> str:
    return crypto_keys.hmac_hex(crypto_keys.K_MSG, _PAYLOAD_FN[table](record))


def _personnel_payload_legacy(r: dict) -> str:
    """The personnel payload as it was BEFORE mission_id was added.

    Adding a field to a signed canonical form invalidates every signature
    made under the old one. The fleet has live personnel records in the
    field right now, and silently invalidating them would lock every
    rescuer out and make sync reject them as forged. So verification
    accepts either form, and new records are always signed with the new
    one. This shim can be deleted once no pre-mission_id records remain.
    """
    return _canon(
        r.get("personnel_id"), r.get("name"), r.get("role"),
        r.get("pin_salt"), r.get("pin_hash"), r.get("pin_algo"),
        r.get("pin_iterations"), r.get("issued_at"), r.get("expires_at"),
        r.get("status"), r.get("updated_at"),
    )


def verify_record(table: str, record: dict) -> bool:
    sig = record.get("signature", "")
    if crypto_keys.verify_hmac_hex(
            crypto_keys.K_MSG, _PAYLOAD_FN[table](record), sig):
        return True
    # Only personnel has a legacy form, and only when the record predates
    # mission scoping. A record that HAS a mission_id must verify under the
    # current payload or not at all, otherwise the legacy path would be a
    # way to strip the scoping.
    if table == "personnel" and not record.get("mission_id"):
        return crypto_keys.verify_hmac_hex(
            crypto_keys.K_MSG, _personnel_payload_legacy(record), sig)
    return False


# ---------------------------------------------------------------------------
# Schema
# ---------------------------------------------------------------------------

def init_db():
    conn = get_conn()
    c = conn.cursor()
    c.execute("PRAGMA journal_mode=WAL;")
    c.execute("PRAGMA foreign_keys=ON;")

    # Design v3 section 3.4 message table + Phase 1 security columns.
    # No Phase 1 migration path on purpose (master plan R6).
    c.execute("""
        CREATE TABLE IF NOT EXISTS messages (
            msg_id TEXT PRIMARY KEY,
            content TEXT,
            user_lat REAL,
            user_lon REAL,
            node_lat REAL,
            node_lon REAL,
            timestamp TEXT,
            time_source TEXT DEFAULT 'relative',
            node_id TEXT,
            status TEXT DEFAULT 'NEW',
            claimed_by TEXT DEFAULT '',
            claimed_at TEXT DEFAULT '',
            synced_from TEXT DEFAULT '',
            signature TEXT,
            is_encrypted INTEGER DEFAULT 0,
            encryption_alg TEXT DEFAULT '',
            encryption_kid TEXT DEFAULT '',
            victim_device_id TEXT DEFAULT '',
            local_ts TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS personnel (
            personnel_id TEXT PRIMARY KEY,
            name TEXT,
            role TEXT DEFAULT 'RESCUE_TEAM',
            pin_salt TEXT,
            pin_hash TEXT,
            pin_algo TEXT DEFAULT 'pbkdf2_sha256',
            pin_iterations INTEGER,
            issued_at TEXT,
            expires_at TEXT,
            status TEXT DEFAULT 'ACTIVE',
            mission_id TEXT DEFAULT '',
            updated_at TEXT,
            signature TEXT,
            local_ts TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS announcements (
            id TEXT PRIMARY KEY,
            title TEXT,
            body TEXT,
            priority TEXT DEFAULT 'NORMAL',
            created_by TEXT,
            created_at TEXT,
            signature TEXT,
            local_ts TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS checkins (
            id TEXT PRIMARY KEY,
            device_id TEXT,
            lat REAL,
            lon REAL,
            accuracy REAL,
            recorded_at TEXT,
            uploaded_at TEXT,
            node_id TEXT,
            sos INTEGER DEFAULT 0,
            signature TEXT,
            local_ts TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS gs_messages (
            id TEXT PRIMARY KEY,
            content TEXT,
            sender TEXT,
            timestamp TEXT,
            node_id TEXT,
            location_lat REAL,
            location_lon REAL,
            location_accuracy REAL,
            location_timestamp TEXT,
            signature TEXT,
            local_ts TEXT
        )
    """)
    # Latest known location per rescuer (M7d). Latest-per-personnel: PK is
    # personnel_id, and sync keeps the newest signed updated_at (same
    # newest-wins pattern as personnel, NOT the append-only checkin pattern).
    c.execute("""
        CREATE TABLE IF NOT EXISTS personnel_locations (
            personnel_id TEXT PRIMARY KEY,
            lat REAL,
            lon REAL,
            accuracy_m REAL,
            battery_pct INTEGER,
            recorded_at TEXT,
            node_id TEXT,
            updated_at TEXT,
            signature TEXT,
            local_ts TEXT
        )
    """)
    # Replies to a victim's message, from rescue or HQ. Replicated like any
    # other record so a reply written at one node reaches the drone the
    # victim actually meets. Keyed by victim_device_id as well as msg_id so
    # a whole conversation can be fetched by device without joining.
    c.execute("""
        CREATE TABLE IF NOT EXISTS message_replies (
            id TEXT PRIMARY KEY,
            msg_id TEXT,
            victim_device_id TEXT,
            body TEXT,
            sender TEXT,
            sender_role TEXT DEFAULT 'RESCUE_TEAM',
            created_at TEXT,
            node_id TEXT,
            signature TEXT,
            local_ts TEXT
        )
    """)
    # Every LoRa frame a node hears, kept as a log rather than only folded
    # into node_health (field backlog #13). node_health answers "is that
    # drone down RIGHT NOW"; this answers "what did it tell us, when, and
    # how well were we hearing it", which is what an operator deciding
    # whether to walk out to a drone actually needs.
    #
    # Replicated on purpose, unlike node_health. The node that hears a
    # beacon is whichever one is nearest the failure, and HQ may be joined
    # to a different one. A log that only exists on the node nobody is
    # looking at is not a log.
    #
    # The same beacon heard by two nodes produces two rows, deliberately.
    # Each carries its own RSSI, and two independent receptions are better
    # evidence than one. The UI groups them.
    c.execute("""
        CREATE TABLE IF NOT EXISTS lora_events (
            id TEXT PRIMARY KEY,
            kind TEXT,
            about_node TEXT,
            heard_by TEXT,
            rssi REAL,
            snr REAL,
            lat REAL,
            lon REAL,
            gps_fix INTEGER DEFAULT 0,
            bat_a_v REAL,
            bat_b_v REAL,
            last_msg TEXT,
            raw TEXT,
            received_at TEXT,
            node_id TEXT,
            signature TEXT,
            local_ts TEXT
        )
    """)
    c.execute("""
        CREATE TABLE IF NOT EXISTS media_attachments (
            id TEXT PRIMARY KEY,
            parent_table TEXT,
            parent_id TEXT,
            filename TEXT,
            mime_type TEXT,
            size_bytes INTEGER,
            sha256 TEXT,
            created_at TEXT,
            node_id TEXT,
            signature TEXT,
            local_ts TEXT
        )
    """)
    c.execute("CREATE INDEX IF NOT EXISTS idx_media_parent "
              "ON media_attachments(parent_table, parent_id)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_lora_events_time "
              "ON lora_events(received_at)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_replies_device "
              "ON message_replies(victim_device_id, created_at)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_messages_device "
              "ON messages(victim_device_id, timestamp)")
    c.execute("""
        CREATE TABLE IF NOT EXISTS node_health (
            node_id TEXT,
            ts TEXT,
            lat REAL,
            lon REAL,
            gps_fix INTEGER,
            bat_a_v REAL,
            bat_a_ma REAL,
            bat_b_v REAL,
            bat_b_ma REAL,
            uptime_s INTEGER,
            clock_source TEXT,
            degraded INTEGER DEFAULT 0
        )
    """)
    # Beacon replay defence (file 09 F6): last accepted counter per peer,
    # counter-based not clock-based because DRONE_S may run on relative time.
    c.execute("""
        CREATE TABLE IF NOT EXISTS peer_state (
            node_id TEXT PRIMARY KEY,
            ip TEXT,
            api_port INTEGER,
            last_counter INTEGER DEFAULT 0,
            last_seen TEXT,
            counts_json TEXT DEFAULT ''
        )
    """)
    # Own persistent counters/state (the beacon counter must survive restarts
    # or peers would reject our post-reboot beacons as replays).
    c.execute("""
        CREATE TABLE IF NOT EXISTS node_state (
            key TEXT PRIMARY KEY,
            value TEXT
        )
    """)
    # Per-peer per-table delta cursor for pull sync (in the peer's local_ts space).
    c.execute("""
        CREATE TABLE IF NOT EXISTS sync_cursor (
            peer_node_id TEXT,
            table_name TEXT,
            last_ts TEXT,
            PRIMARY KEY (peer_node_id, table_name)
        )
    """)
    for table in REPLICATED_TABLES:
        c.execute(f"CREATE INDEX IF NOT EXISTS idx_{table}_local_ts ON {table}(local_ts)")
    c.execute("CREATE INDEX IF NOT EXISTS idx_node_health_node_ts ON node_health(node_id, ts)")

    # CREATE TABLE IF NOT EXISTS does NOT add columns to a table that
    # already exists, and these nodes have live databases, so mission_id
    # has to be added explicitly. Harmless to run every start.
    existing = {r["name"] for r in c.execute("PRAGMA table_info(personnel)")}
    if "mission_id" not in existing:
        c.execute("ALTER TABLE personnel ADD COLUMN mission_id TEXT DEFAULT ''")
    conn.commit()
    conn.close()

    try:
        os.chmod(DB_FILE, 0o600)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# Messages
# ---------------------------------------------------------------------------

def save_message(content, user_lat=None, user_lon=None, is_encrypted=False,
                 encryption_alg="", encryption_kid="", victim_device_id="",
                 node_id=None, synced_from=""):
    """Create a new local message. node_lat/node_lon and time_source come
    from the aux module state (design v3 3.3): before the first GPS time
    sync the node clock is unsynced, so time_source is 'relative' and the
    timestamp is understood as approximate; after sync it is 'gps'."""
    state = aux_state.read_state()
    now = iso_now()
    record = {
        "msg_id": str(uuid.uuid4()),
        "content": content,
        "user_lat": user_lat,
        "user_lon": user_lon,
        "node_lat": state["gps"]["lat"],
        "node_lon": state["gps"]["lon"],
        "timestamp": now,
        "time_source": "gps" if state.get("gps_time_applied") else "relative",
        "node_id": node_id or config.NODE_ID,
        "victim_device_id": victim_device_id or "",
    }
    record["signature"] = sign_record("messages", record)
    conn = get_conn()
    conn.execute("""
        INSERT INTO messages (
            msg_id, content, user_lat, user_lon, node_lat, node_lon,
            timestamp, time_source, node_id, status, claimed_by, claimed_at,
            synced_from, signature, is_encrypted, encryption_alg,
            encryption_kid, victim_device_id, local_ts
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'NEW', '', '', ?, ?, ?, ?, ?, ?, ?)
    """, (
        record["msg_id"], record["content"], record["user_lat"], record["user_lon"],
        record["node_lat"], record["node_lon"], record["timestamp"],
        record["time_source"], record["node_id"], synced_from,
        record["signature"], 1 if is_encrypted else 0, encryption_alg,
        encryption_kid, record["victim_device_id"], now,
    ))
    conn.commit()
    conn.close()
    return record["msg_id"]


def get_all_messages():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM messages ORDER BY timestamp DESC").fetchall()
    msgs = [dict(r) for r in rows]
    msg_ids = [m["msg_id"] for m in msgs]
    if msg_ids:
        placeholders = ",".join("?" for _ in msg_ids)
        att_rows = conn.execute(f"""
            SELECT id, parent_id, filename, mime_type, size_bytes, sha256, created_at
              FROM media_attachments
             WHERE parent_table = 'messages' AND parent_id IN ({placeholders})
             ORDER BY created_at ASC
        """, msg_ids).fetchall()
        att_map = {}
        for a in att_rows:
            ad = dict(a)
            att_map.setdefault(ad["parent_id"], []).append(ad)
        for m in msgs:
            m["attachments"] = att_map.get(m["msg_id"], [])
    else:
        for m in msgs:
            m["attachments"] = []
    conn.close()
    return msgs


def get_message_by_id(msg_id):
    conn = get_conn()
    row = conn.execute("SELECT * FROM messages WHERE msg_id = ?", (msg_id,)).fetchone()
    if not row:
        conn.close()
        return None
    msg = dict(row)
    att_rows = conn.execute("""
        SELECT id, parent_id, filename, mime_type, size_bytes, sha256, created_at
          FROM media_attachments
         WHERE parent_table = 'messages' AND parent_id = ?
         ORDER BY created_at ASC
    """, (msg_id,)).fetchall()
    msg["attachments"] = [dict(a) for a in att_rows]
    conn.close()
    return msg


def get_messages_by_victim_device_id(victim_device_id):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM messages WHERE victim_device_id = ? ORDER BY timestamp ASC",
        (victim_device_id,),
    ).fetchall()
    msgs = [dict(r) for r in rows]
    msg_ids = [m["msg_id"] for m in msgs]
    if msg_ids:
        placeholders = ",".join("?" for _ in msg_ids)
        att_rows = conn.execute(f"""
            SELECT id, parent_id, filename, mime_type, size_bytes, sha256, created_at
              FROM media_attachments
             WHERE parent_table = 'messages' AND parent_id IN ({placeholders})
             ORDER BY created_at ASC
        """, msg_ids).fetchall()
        att_map = {}
        for a in att_rows:
            ad = dict(a)
            att_map.setdefault(ad["parent_id"], []).append(ad)
        for m in msgs:
            m["attachments"] = att_map.get(m["msg_id"], [])
    else:
        for m in msgs:
            m["attachments"] = []
    conn.close()
    return msgs


def claim_message(msg_id, claimed_by):
    now = iso_now()
    conn = get_conn()
    conn.execute(
        """UPDATE messages SET status = 'CLAIMED', claimed_by = ?, claimed_at = ?,
           local_ts = ? WHERE msg_id = ? AND status != 'CLAIMED'""",
        (claimed_by, now, now, msg_id),
    )
    conn.commit()
    conn.close()


def count_messages_by_status(status):
    conn = get_conn()
    count = conn.execute(
        "SELECT COUNT(*) FROM messages WHERE status = ?", (status,)
    ).fetchone()[0]
    conn.close()
    return count


def message_counts():
    conn = get_conn()
    rows = conn.execute("SELECT status, COUNT(*) AS n FROM messages GROUP BY status").fetchall()
    conn.close()
    return {r["status"]: r["n"] for r in rows}


def latest_message_rowid():
    conn = get_conn()
    row = conn.execute("SELECT MAX(rowid) AS r FROM messages").fetchone()
    conn.close()
    return row["r"] or 0


def get_message_after_rowid(rowid):
    """Newest message with rowid greater than the given one (aux bridge push
    path, file 02 task 2.2 point 8). Returns dict with 'rid' or None."""
    conn = get_conn()
    row = conn.execute(
        "SELECT rowid AS rid, * FROM messages WHERE rowid > ? ORDER BY rowid DESC LIMIT 1",
        (rowid,),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


# ---------------------------------------------------------------------------
# Personnel (file 02 task 2.4)
# ---------------------------------------------------------------------------

def _hash_pin(pin: str, salt_hex: str, iterations: int) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256", pin.encode(), bytes.fromhex(salt_hex), iterations
    ).hex()


def write_personnel_record(record: dict, local_ts: str = None):
    """Upsert a fully-formed, signed personnel record. The signed origin
    updated_at travels unchanged; local_ts is this node's cursor stamp."""
    conn = get_conn()
    conn.execute("""
        INSERT OR REPLACE INTO personnel (
            personnel_id, name, role, pin_salt, pin_hash, pin_algo,
            pin_iterations, issued_at, expires_at, status, updated_at,
            mission_id, signature, local_ts
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        record["personnel_id"], record.get("name"), record.get("role"),
        record.get("pin_salt"), record.get("pin_hash"), record.get("pin_algo"),
        record.get("pin_iterations"), record.get("issued_at"),
        record.get("expires_at"), record.get("status"), record.get("updated_at"),
        record.get("mission_id", "") or "",
        record.get("signature"), local_ts or iso_now(),
    ))
    conn.commit()
    conn.close()


def create_personnel(name: str, role: str = "RESCUE_TEAM", expires_hours: int = 0,
                     personnel_id: str = "", mission_id: str = ""):
    """Create or replace a personnel record. Returns (record, plaintext_pin).
    PINs are low entropy, so PBKDF2-SHA256 with >= 200k iterations and a
    16-byte salt (file 02 threat model note); the plaintext PIN exists only
    in this return value, shown once by the GCC, never stored."""
    pin = "".join(secrets.choice("0123456789") for _ in range(config.PIN_LENGTH))
    salt = secrets.token_hex(16)
    now = iso_now()
    prefix = "H" if role == "HQ" else "R"
    if not personnel_id:
        conn = get_conn()
        try:
            for _ in range(100):
                candidate = f"{prefix}-{secrets.randbelow(1000):03d}"
                exists = conn.execute(
                    "SELECT 1 FROM personnel WHERE personnel_id = ?", (candidate,)
                ).fetchone()
                if not exists:
                    personnel_id = candidate
                    break
            else:
                personnel_id = f"{prefix}-{uuid.uuid4().hex[:6]}"
        finally:
            conn.close()
    record = {
        "personnel_id": personnel_id,
        "name": name,
        "role": role,
        "pin_salt": salt,
        "pin_hash": _hash_pin(pin, salt, config.PBKDF2_ITERATIONS),
        "pin_algo": "pbkdf2_sha256",
        "pin_iterations": config.PBKDF2_ITERATIONS,
        "issued_at": now,
        "expires_at": iso_in_hours(expires_hours) if expires_hours else "",
        "status": "ACTIVE",
        "updated_at": now,
        # Which mission this credential belongs to. Starting a new mission
        # retires every credential from the old one at once, with no need
        # to revoke people individually or wait for those revocations to
        # sync (field backlog, 2026-08-05).
        "mission_id": mission_id or "",
    }
    record["signature"] = sign_record("personnel", record)
    write_personnel_record(record, local_ts=now)
    return record, pin


def get_personnel_public():
    """List without hash material (file 02: GET /personnel without hashes)."""
    conn = get_conn()
    rows = conn.execute("""
        SELECT personnel_id, name, role, issued_at, expires_at, status,
               updated_at, mission_id
        FROM personnel ORDER BY issued_at DESC
    """).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_personnel_by_id(personnel_id):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM personnel WHERE personnel_id = ?", (personnel_id,)
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def revoke_personnel(personnel_id):
    """Set status REVOKED and re-sign. Returns False if unknown id.
    Revocation reaches other nodes at DTN sync speed; that latency is a
    documented property (file 02 task 2.4)."""
    record = get_personnel_by_id(personnel_id)
    if not record:
        return False
    record["status"] = "REVOKED"
    record["updated_at"] = iso_now()
    record["signature"] = sign_record("personnel", record)
    write_personnel_record(record)
    return True


def verify_pin(personnel_id: str, pin: str):
    """Return the personnel record when the PIN verifies against the LOCAL
    table (which syncs fleet-wide) and the record is usable, else None."""
    record = get_personnel_by_id(personnel_id)
    if not record or record["status"] != "ACTIVE":
        return None
    if record["expires_at"] and record["expires_at"] < iso_now():
        return None
    computed = _hash_pin(pin, record["pin_salt"], int(record["pin_iterations"]))
    if not hmac_mod.compare_digest(record["pin_hash"], computed):
        return None
    return record


# ---------------------------------------------------------------------------
# Announcements
# ---------------------------------------------------------------------------

def save_announcement(title, body, priority, created_by):
    now = iso_now()
    record = {
        "id": str(uuid.uuid4()),
        "title": title,
        "body": body,
        "priority": priority,
        "created_by": created_by,
        "created_at": now,
    }
    record["signature"] = sign_record("announcements", record)
    conn = get_conn()
    conn.execute("""
        INSERT INTO announcements (id, title, body, priority, created_by,
                                   created_at, signature, local_ts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (record["id"], record["title"], record["body"], record["priority"],
          record["created_by"], record["created_at"], record["signature"], now))
    conn.commit()
    conn.close()
    return record["id"]


def get_announcements():
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM announcements ORDER BY created_at DESC"
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Checkins (file 02 task 2.5, emergency app data)
# ---------------------------------------------------------------------------

def save_checkin(device_id, lat, lon, accuracy, recorded_at, sos=0):
    now = iso_now()
    record = {
        "id": str(uuid.uuid4()),
        "device_id": device_id,
        "lat": lat,
        "lon": lon,
        "accuracy": accuracy,
        "recorded_at": recorded_at,
        "node_id": config.NODE_ID,
        "sos": 1 if sos else 0,
    }
    record["signature"] = sign_record("checkins", record)
    conn = get_conn()
    conn.execute("""
        INSERT INTO checkins (id, device_id, lat, lon, accuracy, recorded_at,
                              uploaded_at, node_id, sos, signature, local_ts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (record["id"], record["device_id"], record["lat"], record["lon"],
          record["accuracy"], record["recorded_at"], now, record["node_id"],
          record["sos"], record["signature"], now))
    conn.commit()
    conn.close()
    return record["id"]


def get_checkins():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM checkins ORDER BY recorded_at DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Personnel locations (M7d): latest-per-rescuer, signed, replicated
# ---------------------------------------------------------------------------

def save_personnel_location(personnel_id, lat, lon, accuracy_m=None,
                            battery_pct=None):
    """Record a rescuer's latest position (from the rescue app heartbeat).
    Signs the record and upserts by personnel_id; updated_at is the signed
    origin timestamp used for newest-wins at sync."""
    now = iso_now()
    record = {
        "personnel_id": personnel_id,
        "lat": lat,
        "lon": lon,
        "accuracy_m": accuracy_m,
        "battery_pct": battery_pct,
        "recorded_at": now,
        "node_id": config.NODE_ID,
        "updated_at": now,
    }
    record["signature"] = sign_record("personnel_locations", record)
    write_personnel_location_record(record, now)
    return record


def write_personnel_location_record(record: dict, local_ts: str = None):
    """Upsert a fully-formed, signed location record (used by both the API
    write and the sync ingest). The signed origin updated_at travels
    unchanged; local_ts is this node's cursor stamp."""
    conn = get_conn()
    conn.execute("""
        INSERT OR REPLACE INTO personnel_locations (
            personnel_id, lat, lon, accuracy_m, battery_pct, recorded_at,
            node_id, updated_at, signature, local_ts
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        record["personnel_id"], record.get("lat"), record.get("lon"),
        record.get("accuracy_m"), record.get("battery_pct"),
        record.get("recorded_at"), record.get("node_id"),
        record.get("updated_at"), record.get("signature"),
        local_ts or iso_now(),
    ))
    conn.commit()
    conn.close()


def get_personnel_location_by_id(personnel_id: str):
    conn = get_conn()
    row = conn.execute(
        "SELECT * FROM personnel_locations WHERE personnel_id = ?",
        (personnel_id,),
    ).fetchone()
    conn.close()
    return dict(row) if row else None


def get_personnel_locations(include_inactive: bool = False):
    """Latest position per rescuer, ACTIVE personnel only by default.

    Revoking someone used to leave their location row in place, so the GCC
    went on counting and plotting them as a tracked rescuer indefinitely
    (field backlog #18). Revocation means they are no longer on the team,
    so they should stop being tracked; filtering here fixes it for every
    client at once rather than in each UI.

    A location whose personnel record has not reached this node yet is
    KEPT, because the alternative is worse: dropping a real rescuer's
    position merely because personnel sync is a cycle behind would hide
    someone who is out there working. Unknown is not the same as revoked.
    """
    conn = get_conn()
    if include_inactive:
        rows = conn.execute(
            "SELECT * FROM personnel_locations ORDER BY updated_at DESC"
        ).fetchall()
    else:
        rows = conn.execute("""
            SELECT pl.* FROM personnel_locations pl
              LEFT JOIN personnel p ON p.personnel_id = pl.personnel_id
             WHERE p.personnel_id IS NULL OR p.status = 'ACTIVE'
             ORDER BY pl.updated_at DESC
        """).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# GS messages (field reports); now signed and replicated
# ---------------------------------------------------------------------------

def save_gs_message(content, sender, location_lat=None, location_lon=None,
                    location_accuracy=None, location_timestamp=None):
    now = iso_now()
    record = {
        "id": str(uuid.uuid4()),
        "content": content,
        "sender": sender,
        "timestamp": now,
        "node_id": config.NODE_ID,
        "location_lat": location_lat,
        "location_lon": location_lon,
    }
    record["signature"] = sign_record("gs_messages", record)
    conn = get_conn()
    conn.execute("""
        INSERT INTO gs_messages (id, content, sender, timestamp, node_id,
                                 location_lat, location_lon, location_accuracy,
                                 location_timestamp, signature, local_ts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (record["id"], record["content"], record["sender"], record["timestamp"],
          record["node_id"], record["location_lat"], record["location_lon"],
          location_accuracy, location_timestamp, record["signature"], now))
    conn.commit()
    conn.close()
    return record["id"]


def get_gs_messages():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM gs_messages ORDER BY timestamp DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Node health (local snapshots + fallback beacon reports; NOT replicated,
# every node keeps what it has observed)
# ---------------------------------------------------------------------------

# Rows of per-node health history to retain (see save_node_health).
NODE_HEALTH_KEEP_ROWS = 50


def save_node_health(node_id, lat=None, lon=None, gps_fix=0, bat_a_v=None,
                     bat_a_ma=None, bat_b_v=None, bat_b_ma=None, uptime_s=None,
                     clock_source="relative", degraded=0, ts=None):
    conn = get_conn()
    conn.execute("""
        INSERT INTO node_health (node_id, ts, lat, lon, gps_fix, bat_a_v,
                                 bat_a_ma, bat_b_v, bat_b_ma, uptime_s,
                                 clock_source, degraded)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (node_id, ts or iso_now(), lat, lon, gps_fix, bat_a_v, bat_a_ma,
          bat_b_v, bat_b_ma, uptime_s, clock_source, 1 if degraded else 0))
    # Bounded history per node. This table is append-only and written on a
    # timer for ourselves AND for every peer we fetch health from, so on a
    # long deployment it would grow without limit on the SD card. Only the
    # newest row per node is ever read (latest_node_health), so keep a short
    # tail for debugging and drop the rest.
    conn.execute("""
        DELETE FROM node_health
         WHERE node_id = ?
           AND ts NOT IN (SELECT ts FROM node_health WHERE node_id = ?
                          ORDER BY ts DESC LIMIT ?)
    """, (node_id, node_id, NODE_HEALTH_KEEP_ROWS))
    conn.commit()
    conn.close()


def save_message_reply(msg_id, victim_device_id, body, sender, sender_role):
    """A rescuer or HQ replying to a victim. Signed like every other
    replicated record so it survives the trip across the mesh."""
    rid = str(uuid.uuid4())
    record = {
        "id": rid,
        "msg_id": msg_id,
        "victim_device_id": victim_device_id,
        "body": body,
        "sender": sender,
        "sender_role": sender_role,
        "created_at": iso_now(),
        "node_id": config.NODE_ID,
    }
    record["signature"] = sign_record("message_replies", record)
    conn = get_conn()
    conn.execute("""
        INSERT INTO message_replies (id, msg_id, victim_device_id, body,
                                     sender, sender_role, created_at,
                                     node_id, signature, local_ts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (rid, msg_id, victim_device_id, body, sender, sender_role,
          record["created_at"], config.NODE_ID, record["signature"], iso_now()))
    conn.commit()
    conn.close()
    return record


def save_media_attachment(parent_table: str, parent_id: str, filename: str,
                          mime_type: str, size_bytes: int, sha256: str,
                          node_id: str = None, media_id: str = None,
                          created_at: str = None) -> dict:
    """Record a media attachment (voice note, photo) in SQLite.
    The binary file itself is stored in config.MEDIA_DIR.
    Signed with K_MSG over the canonical field order."""
    mid = media_id or str(uuid.uuid4())
    now = created_at or iso_now()
    nid = node_id or config.NODE_ID
    record = {
        "id": mid,
        "parent_table": parent_table,
        "parent_id": parent_id,
        "filename": filename,
        "mime_type": mime_type,
        "size_bytes": size_bytes,
        "sha256": sha256,
        "created_at": now,
        "node_id": nid,
    }
    record["signature"] = sign_record("media_attachments", record)
    conn = get_conn()
    conn.execute("""
        INSERT INTO media_attachments (
            id, parent_table, parent_id, filename, mime_type, size_bytes,
            sha256, created_at, node_id, signature, local_ts
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        record["id"], record["parent_table"], record["parent_id"],
        record["filename"], record["mime_type"], record["size_bytes"],
        record["sha256"], record["created_at"], record["node_id"],
        record["signature"], iso_now(),
    ))
    conn.commit()
    conn.close()
    return record


def get_media_attachment(media_id: str) -> Optional[dict]:
    conn = get_conn()
    row = conn.execute("SELECT * FROM media_attachments WHERE id = ?", (media_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_media_attachments_for_parent(parent_table: str, parent_id: str) -> list:
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM media_attachments WHERE parent_table = ? AND parent_id = ? ORDER BY created_at ASC",
        (parent_table, parent_id),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_media_attachments_for_parents(parent_table: str, parent_ids: list) -> dict:
    if not parent_ids:
        return {}
    conn = get_conn()
    placeholders = ",".join("?" for _ in parent_ids)
    rows = conn.execute(
        f"SELECT * FROM media_attachments WHERE parent_table = ? AND parent_id IN ({placeholders}) ORDER BY created_at ASC",
        [parent_table, *parent_ids],
    ).fetchall()
    conn.close()
    result = {pid: [] for pid in parent_ids}
    for r in rows:
        d = dict(r)
        result[d["parent_id"]].append(d)
    return result


def get_all_media_ids() -> set:
    conn = get_conn()
    rows = conn.execute("SELECT id FROM media_attachments").fetchall()
    conn.close()
    return {r["id"] for r in rows}


def get_all_media_attachments() -> list:
    conn = get_conn()
    rows = conn.execute("SELECT * FROM media_attachments ORDER BY created_at DESC").fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_conversation(victim_device_id: str) -> dict:
    """Everything one victim device has sent and been told, oldest first.

    Scoped strictly to the caller's own device id. The victim plane has no
    other read endpoint, and this one must never become a way to enumerate
    other people's emergencies, so there is no "list all conversations"
    variant here by design.
    """
    conn = get_conn()
    msgs = conn.execute("""
        SELECT msg_id, content, timestamp, time_source, status, claimed_at,
               user_lat, user_lon, node_id, is_encrypted
          FROM messages
         WHERE victim_device_id = ?
         ORDER BY timestamp ASC
    """, (victim_device_id,)).fetchall()
    msg_rows = [dict(m) for m in msgs]
    msg_ids = [m["msg_id"] for m in msg_rows]

    attachments_by_msg = {}
    if msg_ids:
        placeholders = ",".join("?" for _ in msg_ids)
        att_rows = conn.execute(f"""
            SELECT id, parent_id, filename, mime_type, size_bytes, sha256, created_at
              FROM media_attachments
             WHERE parent_table = 'messages' AND parent_id IN ({placeholders})
             ORDER BY created_at ASC
        """, msg_ids).fetchall()
        for a in att_rows:
            ad = dict(a)
            attachments_by_msg.setdefault(ad["parent_id"], []).append(ad)

    for m in msg_rows:
        m["attachments"] = attachments_by_msg.get(m["msg_id"], [])

    replies = conn.execute("""
        SELECT id, msg_id, body, sender, sender_role, created_at, node_id
          FROM message_replies
         WHERE victim_device_id = ?
         ORDER BY created_at ASC
    """, (victim_device_id,)).fetchall()
    conn.close()
    return {
        "messages": msg_rows,
        "replies": [dict(r) for r in replies],
    }


def area_map_snapshot(include_rescuers: bool = True,
                      victim_hours: float = 24.0) -> dict:
    """Positions to draw on the victim app's map.

    The operator decided this is shared openly: in Sri Lankan floods people
    already publish their location publicly to seek help, and neighbours
    reach them faster than responders can. Rescuers here are typically army
    who are publicly deployed and announced, so their positions are shared
    too, behind a mission-config flag in case a deployment decides
    otherwise (CHANGES.md item 38).

    What is deliberately NOT included, even under that decision: message
    CONTENT and device ids. Someone looking at this map needs to know that
    a person nearby needs help and roughly how urgently. They do not need
    to read that person's medical details or be able to link two positions
    to the same individual over time. Positions only keeps the whole
    benefit and drops most of the harm.
    """
    conn = get_conn()
    since = (datetime.now(timezone.utc)
             - timedelta(hours=victim_hours)).strftime("%Y-%m-%dT%H:%M:%S.%fZ")

    drones = conn.execute("""
        SELECT nh.node_id, nh.lat, nh.lon, nh.gps_fix
          FROM node_health nh
          JOIN (SELECT node_id, MAX(ts) AS mts FROM node_health GROUP BY node_id) m
            ON nh.node_id = m.node_id AND nh.ts = m.mts
         WHERE nh.lat IS NOT NULL AND nh.lon IS NOT NULL
    """).fetchall()

    victims = conn.execute("""
        SELECT user_lat AS lat, user_lon AS lon, status
          FROM messages
         WHERE user_lat IS NOT NULL AND user_lon IS NOT NULL
           AND timestamp > ?
    """, (since,)).fetchall()

    rescuers = []
    if include_rescuers:
        rescuers = conn.execute("""
            SELECT lat, lon FROM personnel_locations
             WHERE lat IS NOT NULL AND lon IS NOT NULL
               AND updated_at > ?
        """, (since,)).fetchall()
    conn.close()

    return {
        "drones": [
            {"node_id": d["node_id"], "lat": d["lat"], "lon": d["lon"]}
            for d in drones
        ],
        # No content, no ids: just "someone here needs help", and whether
        # anyone has picked it up yet.
        "victims": [
            {"lat": v["lat"], "lon": v["lon"],
             "helped": v["status"] == "CLAIMED"}
            for v in victims
        ],
        "rescuers": [{"lat": r["lat"], "lon": r["lon"]} for r in rescuers],
    }


def latest_node_health():
    """Latest health row per node_id."""
    conn = get_conn()
    rows = conn.execute("""
        SELECT nh.* FROM node_health nh
        JOIN (SELECT node_id, MAX(ts) AS mts FROM node_health GROUP BY node_id) m
          ON nh.node_id = m.node_id AND nh.ts = m.mts
    """).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Peer state / beacon counters (file 09 F6) and own persistent counter
# ---------------------------------------------------------------------------

def get_peer_state(node_id):
    conn = get_conn()
    row = conn.execute("SELECT * FROM peer_state WHERE node_id = ?", (node_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def accept_beacon(node_id, ip, api_port, counter, counts_json):
    """Atomically accept a beacon only if its counter is strictly greater
    than the last accepted one for this node (replay defence, file 09 F6).
    Returns True when accepted."""
    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        cur = conn.execute(
            "SELECT last_counter FROM peer_state WHERE node_id = ?", (node_id,)
        ).fetchone()
        if cur is not None and counter <= cur["last_counter"]:
            conn.rollback()
            return False
        conn.execute("""
            INSERT INTO peer_state (node_id, ip, api_port, last_counter, last_seen, counts_json)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(node_id) DO UPDATE SET
                ip = excluded.ip, api_port = excluded.api_port,
                last_counter = excluded.last_counter,
                last_seen = excluded.last_seen, counts_json = excluded.counts_json
        """, (node_id, ip, api_port, counter, iso_now(), counts_json))
        conn.commit()
        return True
    finally:
        conn.close()


def alive_peers(expiry_seconds):
    horizon = (datetime.now(timezone.utc) - timedelta(seconds=expiry_seconds)).strftime(
        "%Y-%m-%dT%H:%M:%S.%fZ"
    )
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM peer_state WHERE last_seen > ?", (horizon,)
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def all_peers():
    conn = get_conn()
    rows = conn.execute("SELECT * FROM peer_state").fetchall()
    conn.close()
    return [dict(r) for r in rows]


def next_beacon_counter() -> int:
    """Monotonic, persisted across restarts (otherwise peers would reject
    our post-reboot beacons as replays)."""
    conn = get_conn()
    try:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute(
            "SELECT value FROM node_state WHERE key = 'beacon_counter'"
        ).fetchone()
        counter = (int(row["value"]) if row else 0) + 1
        conn.execute("""
            INSERT INTO node_state (key, value) VALUES ('beacon_counter', ?)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value
        """, (str(counter),))
        conn.commit()
        return counter
    finally:
        conn.close()


# ---------------------------------------------------------------------------
# Delta sync support
# ---------------------------------------------------------------------------

def get_rows_since(table: str, since: str, limit: int):
    if table not in REPLICATED_TABLES:
        raise ValueError(f"not a replicated table: {table}")
    conn = get_conn()
    rows = conn.execute(
        f"SELECT * FROM {table} WHERE local_ts > ? ORDER BY local_ts ASC LIMIT ?",
        (since or "", limit),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def get_sync_cursor(peer_node_id: str, table: str) -> str:
    conn = get_conn()
    row = conn.execute(
        "SELECT last_ts FROM sync_cursor WHERE peer_node_id = ? AND table_name = ?",
        (peer_node_id, table),
    ).fetchone()
    conn.close()
    return row["last_ts"] if row else ""


def set_sync_cursor(peer_node_id: str, table: str, last_ts: str):
    conn = get_conn()
    conn.execute("""
        INSERT INTO sync_cursor (peer_node_id, table_name, last_ts) VALUES (?, ?, ?)
        ON CONFLICT(peer_node_id, table_name) DO UPDATE SET last_ts = excluded.last_ts
    """, (peer_node_id, table, last_ts))
    conn.commit()
    conn.close()


def table_counts():
    conn = get_conn()
    counts = {}
    for table in REPLICATED_TABLES:
        counts[table] = conn.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    conn.close()
    return counts


# --- LoRa event log (field backlog #13) -------------------------------------

def save_lora_event(kind: str, about_node: str, raw: str, *, rssi=None,
                    snr=None, lat=None, lon=None, gps_fix=0, bat_a_v=None,
                    bat_b_v=None, last_msg: str = "") -> dict:
    """Record one LoRa frame this node heard.

    The id is derived from the CONTENT plus which node heard it, not from a
    random uuid, so a frame replicated back to us from a peer that also
    heard it collides on the primary key instead of appearing twice. Two
    different receivers still produce two rows, which is intended.
    """
    received_at = iso_now()
    ident = crypto_keys.hmac_hex(
        crypto_keys.K_MSG,
        "lora|" + "|".join([config.NODE_ID, raw, received_at]),
    )[:32]
    record = {
        "id": ident,
        "kind": kind,
        "about_node": about_node,
        "heard_by": config.NODE_ID,
        "received_at": received_at,
        "raw": raw,
    }
    record["signature"] = sign_record("lora_events", record)
    conn = get_conn()
    conn.execute("""
        INSERT OR IGNORE INTO lora_events
          (id, kind, about_node, heard_by, rssi, snr, lat, lon, gps_fix,
           bat_a_v, bat_b_v, last_msg, raw, received_at, node_id, signature,
           local_ts)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (ident, kind, about_node, config.NODE_ID, rssi, snr, lat, lon,
          1 if gps_fix else 0, bat_a_v, bat_b_v, last_msg, raw, received_at,
          config.NODE_ID, record["signature"], iso_now()))
    conn.commit()
    conn.close()
    return record


def get_lora_events(limit: int = 200, since: str = "") -> list:
    """Newest first. `since` filters on received_at for cheap polling."""
    conn = get_conn()
    if since:
        rows = conn.execute(
            "SELECT * FROM lora_events WHERE received_at > ? "
            "ORDER BY received_at DESC LIMIT ?", (since, limit)).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM lora_events ORDER BY received_at DESC LIMIT ?",
            (limit,)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


# A busy fallback (a beacon every 30 s per node) would otherwise grow this
# table without bound on a long deployment. Kept generous: the whole point
# is being able to look back over an incident.
LORA_EVENTS_KEEP_ROWS = 2000


def prune_lora_events(keep: int = LORA_EVENTS_KEEP_ROWS) -> int:
    conn = get_conn()
    cur = conn.execute("""
        DELETE FROM lora_events WHERE id NOT IN (
            SELECT id FROM lora_events ORDER BY received_at DESC LIMIT ?
        )
    """, (keep,))
    conn.commit()
    removed = cur.rowcount or 0
    conn.close()
    return removed
