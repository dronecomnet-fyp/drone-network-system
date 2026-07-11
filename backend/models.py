import sqlite3
import uuid
import time
import os
import hmac
import hashlib

DB_FILE = "drone_mesh.db"
NODE_SHARED_SECRET = os.getenv("NODE_SHARED_SECRET", "mesh_signing_change_me")


def sign_message(msg_id, content, timestamp):
    payload = f"{msg_id}:{content}:{timestamp}"
    return hmac.new(NODE_SHARED_SECRET.encode(), payload.encode(), hashlib.sha256).hexdigest()


def verify_message_signature(msg_id, content, timestamp, signature):
    expected = sign_message(msg_id, content, timestamp)
    return hmac.compare_digest(expected, signature)

def init_db():
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("PRAGMA journal_mode=WAL;")
    c.execute("PRAGMA foreign_keys=ON;")
    c.execute('''
        CREATE TABLE IF NOT EXISTS messages (
            msg_id TEXT PRIMARY KEY,
            content TEXT,
            location TEXT,
            timestamp REAL,
            origin_node TEXT,
            synced INTEGER DEFAULT 0,
            status TEXT DEFAULT 'NEW',
            signature TEXT,
            is_encrypted INTEGER DEFAULT 0,
            encryption_alg TEXT DEFAULT '',
            encryption_kid TEXT DEFAULT '',
            victim_device_id TEXT DEFAULT '',
            location_lat REAL,
            location_lon REAL,
            location_accuracy REAL,
            location_timestamp REAL
        )
    ''')
    c.execute('''
        CREATE TABLE IF NOT EXISTS gs_messages (
            id TEXT PRIMARY KEY,
            content TEXT,
            sender TEXT,
            timestamp REAL
        )
    ''')

    # Add optional GPS columns for gs_messages if not present
    c.execute("PRAGMA table_info(gs_messages)")
    gs_cols = {row[1] for row in c.fetchall()}
    if "location_lat" not in gs_cols:
        try:
            c.execute("ALTER TABLE gs_messages ADD COLUMN location_lat REAL")
        except sqlite3.OperationalError:
            pass
    if "location_lon" not in gs_cols:
        try:
            c.execute("ALTER TABLE gs_messages ADD COLUMN location_lon REAL")
        except sqlite3.OperationalError:
            pass
    if "location_accuracy" not in gs_cols:
        try:
            c.execute("ALTER TABLE gs_messages ADD COLUMN location_accuracy REAL")
        except sqlite3.OperationalError:
            pass
    if "location_timestamp" not in gs_cols:
        try:
            c.execute("ALTER TABLE gs_messages ADD COLUMN location_timestamp REAL")
        except sqlite3.OperationalError:
            pass

    # Lightweight migration for existing databases created before signature support.
    c.execute("PRAGMA table_info(messages)")
    columns = {row[1] for row in c.fetchall()}
    if "signature" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN signature TEXT")
    if "is_encrypted" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN is_encrypted INTEGER DEFAULT 0")
    if "encryption_alg" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN encryption_alg TEXT DEFAULT ''")
    if "encryption_kid" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN encryption_kid TEXT DEFAULT ''")
    if "victim_device_id" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN victim_device_id TEXT DEFAULT ''")
    if "location_lat" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN location_lat REAL")
    if "location_lon" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN location_lon REAL")
    if "location_accuracy" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN location_accuracy REAL")
    if "location_timestamp" not in columns:
        c.execute("ALTER TABLE messages ADD COLUMN location_timestamp REAL")

    # Backfill signatures for legacy rows created before signature support.
    c.execute("SELECT msg_id, content, timestamp FROM messages WHERE signature IS NULL OR signature = ''")
    unsigned_rows = c.fetchall()
    for msg_id, content, timestamp in unsigned_rows:
        signature = sign_message(msg_id, content, timestamp)
        c.execute("UPDATE messages SET signature = ? WHERE msg_id = ?", (signature, msg_id))

    conn.commit()
    conn.close()

    # Best-effort local hardening for data-at-rest file permissions.
    try:
        os.chmod(DB_FILE, 0o600)
    except OSError:
        pass

    print("[*] Database initialized.")

def save_message(content, location, origin_node, is_encrypted=False, encryption_alg="", encryption_kid="", victim_device_id="", location_lat=None, location_lon=None, location_accuracy=None, location_timestamp=None):
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    msg_id = str(uuid.uuid4())
    timestamp = time.time()
    signature = sign_message(msg_id, content, timestamp)
    
    c.execute('''
        INSERT INTO messages (
            msg_id, content, location, timestamp, origin_node,
            synced, status, signature, is_encrypted, encryption_alg, encryption_kid,
            victim_device_id, location_lat, location_lon, location_accuracy, location_timestamp
        )
        VALUES (?, ?, ?, ?, ?, 0, 'NEW', ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        msg_id,
        content,
        location,
        timestamp,
        origin_node,
        signature,
        1 if is_encrypted else 0,
        encryption_alg,
        encryption_kid,
        victim_device_id,
        location_lat,
        location_lon,
        location_accuracy,
        location_timestamp,
    ))
    
    conn.commit()
    conn.close()
    return msg_id

def get_all_messages():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute("SELECT * FROM messages ORDER BY timestamp DESC")
    rows = c.fetchall()
    conn.close()
    return [dict(row) for row in rows]

def claim_message(msg_id):
    """Update message status to CLAIMED"""
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("UPDATE messages SET status = 'CLAIMED' WHERE msg_id = ?", (msg_id,))
    conn.commit()
    conn.close()

def save_gs_message(content, sender, location_lat=None, location_lon=None, location_accuracy=None, location_timestamp=None):
    """Save a message from field team to ground station. Accepts optional GPS fields."""
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    msg_id = str(uuid.uuid4())
    timestamp = time.time()
    # Insert with optional GPS values (may be None)
    c.execute('''
        INSERT INTO gs_messages (
            id, content, sender, timestamp,
            location_lat, location_lon, location_accuracy, location_timestamp
        )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        msg_id,
        content,
        sender,
        timestamp,
        location_lat,
        location_lon,
        location_accuracy,
        location_timestamp,
    ))
    
    conn.commit()
    conn.close()
    return msg_id

def get_gs_messages():
    """Retrieve all ground station messages"""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    # Select new GPS columns if present in schema
    try:
        c.execute("SELECT id, content, sender, timestamp, location_lat, location_lon, location_accuracy, location_timestamp FROM gs_messages ORDER BY timestamp DESC")
    except sqlite3.OperationalError:
        # Fallback for older DBs without the new columns
        c.execute("SELECT id, content, sender, timestamp FROM gs_messages ORDER BY timestamp DESC")
    rows = c.fetchall()
    conn.close()
    return [dict(row) for row in rows]

def get_message_by_id(msg_id):
    """Get a specific message by ID"""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute("SELECT * FROM messages WHERE msg_id = ?", (msg_id,))
    row = c.fetchone()
    conn.close()
    return dict(row) if row else None

def update_message_status(msg_id, status):
    """Update message status to the given value"""
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("UPDATE messages SET status = ? WHERE msg_id = ?", (status, msg_id))
    conn.commit()
    conn.close()


def count_messages_by_status(status):
    """Count messages by status value."""
    conn = sqlite3.connect(DB_FILE)
    c = conn.cursor()
    c.execute("SELECT COUNT(*) FROM messages WHERE status = ?", (status,))
    count = c.fetchone()[0]
    conn.close()
    return count

def get_messages_by_victim_device_id(victim_device_id):
    """Get all messages from a specific victim device (for follow-up tracking)."""
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    c.execute("SELECT * FROM messages WHERE victim_device_id = ? ORDER BY timestamp ASC", (victim_device_id,))
    rows = c.fetchall()
    conn.close()
    return [dict(row) for row in rows]
