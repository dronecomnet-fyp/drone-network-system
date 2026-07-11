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

import hashlib
import hmac as hmac_mod
import os
import secrets
import sqlite3
import uuid
from datetime import datetime, timedelta, timezone

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
    return _canon(
        r.get("personnel_id"), r.get("name"), r.get("role"),
        r.get("pin_salt"), r.get("pin_hash"), r.get("pin_algo"),
        r.get("pin_iterations"), r.get("issued_at"), r.get("expires_at"),
        r.get("status"), r.get("updated_at"),
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


_PAYLOAD_FN = {
    "messages": _message_payload,
    "personnel": _personnel_payload,
    "announcements": _announcement_payload,
    "gs_messages": _gs_message_payload,
    "checkins": _checkin_payload,
}


def sign_record(table: str, record: dict) -> str:
    return crypto_keys.hmac_hex(crypto_keys.K_MSG, _PAYLOAD_FN[table](record))


def verify_record(table: str, record: dict) -> bool:
    return crypto_keys.verify_hmac_hex(
        crypto_keys.K_MSG, _PAYLOAD_FN[table](record), record.get("signature", "")
    )


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
    conn.close()
    return [dict(r) for r in rows]


def get_message_by_id(msg_id):
    conn = get_conn()
    row = conn.execute("SELECT * FROM messages WHERE msg_id = ?", (msg_id,)).fetchone()
    conn.close()
    return dict(row) if row else None


def get_messages_by_victim_device_id(victim_device_id):
    conn = get_conn()
    rows = conn.execute(
        "SELECT * FROM messages WHERE victim_device_id = ? ORDER BY timestamp ASC",
        (victim_device_id,),
    ).fetchall()
    conn.close()
    return [dict(r) for r in rows]


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
            signature, local_ts
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        record["personnel_id"], record.get("name"), record.get("role"),
        record.get("pin_salt"), record.get("pin_hash"), record.get("pin_algo"),
        record.get("pin_iterations"), record.get("issued_at"),
        record.get("expires_at"), record.get("status"), record.get("updated_at"),
        record.get("signature"), local_ts or iso_now(),
    ))
    conn.commit()
    conn.close()


def create_personnel(name: str, role: str = "RESCUE_TEAM", expires_hours: int = 0,
                     personnel_id: str = ""):
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
    }
    record["signature"] = sign_record("personnel", record)
    write_personnel_record(record, local_ts=now)
    return record, pin


def get_personnel_public():
    """List without hash material (file 02: GET /personnel without hashes)."""
    conn = get_conn()
    rows = conn.execute("""
        SELECT personnel_id, name, role, issued_at, expires_at, status, updated_at
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
    conn.commit()
    conn.close()


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
