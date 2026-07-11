# 02 BACKEND V2: SCHEMA, ALWAYS-ON SYNC, AUX BRIDGE, PERSONNEL AUTH, NEW ENDPOINTS

Applies to `backend/` (rpi_ prefixed files in the project store). Keep the
existing security model (role keys, HMAC signatures, audit log, optional
TLS/mTLS) and extend it. Do not weaken any Phase 1 control.

## Task 2.1 Schema v3 (models.py rewrite)

Implement the message table exactly per design v3 section 3.4:
msg_id (TEXT PK), content, user_lat, user_lon, node_lat, node_lon,
timestamp (TEXT ISO 8601 UTC), time_source ("gps"|"relative"), node_id,
status (NEW|CLAIMED), claimed_by, synced_from, plus keep the Phase 1 security
columns: signature, is_encrypted, encryption_alg, encryption_kid,
victim_device_id.

Add tables:
- personnel(personnel_id TEXT PK, name, role, pin_salt, pin_hash,
  pin_algo TEXT DEFAULT 'pbkdf2_sha256', pin_iterations INTEGER,
  issued_at, expires_at, status TEXT DEFAULT 'ACTIVE', updated_at,
  signature)  -- signature = HMAC over the record fields with
  NODE_SHARED_SECRET so forged records are rejected during sync.
- announcements(id TEXT PK, title, body, priority, created_by, created_at,
  signature)
- checkins(id TEXT PK, device_id, lat, lon, accuracy, recorded_at,
  uploaded_at, node_id, sos INTEGER DEFAULT 0)
- node_health(node_id, ts, lat, lon, gps_fix, bat_a_v, bat_a_ma, bat_b_v,
  bat_b_ma, uptime_s, clock_source, degraded INTEGER DEFAULT 0)
- gs_messages: keep, add signature column so it can sync (see 2.3).

HMAC signing: extend the existing sign/verify helpers to cover personnel,
announcements, gs_messages, and checkins with a canonical field order per
table. Timestamps in ISO 8601 UTC strings everywhere new; keep epoch floats
only where Phase 1 compatibility inside a table demands it (it does not,
because databases are wiped per master plan D1/R6).

No migration code from Phase 1 DBs. init_db() creates v3 fresh. State this
in a comment referencing master plan R6.

## Task 2.2 Aux-bridge daemon (new file backend/aux_bridge.py)

Purpose: the Pi side of the design v3 serial protocol (section 3.1 table).
Runs as rescue-mesh-auxbridge.service. If AUX_SERIAL is empty in node.env
(DRONE_S flies without an aux module, file 08), the service exits cleanly
at start and /health reports aux: absent; everything else on the node must
work unchanged, with time_source staying "relative" on that node.

Behavior:
1. Open AUX_SERIAL at 115200, newline-delimited JSON both directions.
   Reconnect loop with backoff if the port disappears.
2. Send {"type":"ping"} every 5 s.
3. On {"type":"gps",...}: cache latest fix in a small state file or shared
   sqlite row; write a node_health snapshot every 30 s.
4. On {"type":"gps_time","utc":...,"fix":1}: set the system clock ONCE at
   startup and then re-sync every 60 minutes (design v3 3.3). Implement via
   `sudo /bin/date -u -s <utc>` allowed by a narrow sudoers entry for the
   service user (deploy/ adds the sudoers file). Log every sync to the audit
   log with old/new time.
5. On {"type":"battery",...}: include in the next node_health snapshot.
6. On {"type":"fallback_rx",...}: store to node_health with degraded=1 for
   the reporting node_id, and audit-log it.
7. Provide a tiny local API for other backend code: simplest is writing the
   latest state as JSON to /run/rescue-mesh/aux_state.json atomically;
   api.py's /health reads it.
8. Push path: watch for new rows (poll the messages table for max rowid every
   2 s, or expose an internal localhost hook the API calls after insert) and
   send {"type":"last_msg", msg_id, content(<=100 chars), timestamp}; also
   forward {"type":"lora_tx"} summaries per design v3 step 6 and
   {"type":"ble_update"} once at startup with the node's SSID and node_id.

time_source flag: models.save_message() asks aux state whether GPS time has
been applied; before that, timestamps are seconds-since-boot mapped into the
message with time_source="relative" per design v3 3.3. After sync,
time_source="gps".

## Task 2.3 Always-on sync daemon (rewrite sync_engine.py + new sync_daemon.py)

Replaces switcher.py entirely.

Presence: every 10 s broadcast UDP to 10.99.0.255:48555 a signed beacon
{node_id, api_port, ts, counts:{messages, personnel, announcements,
gs_messages, checkins}} using NODE_SHARED_SECRET HMAC. Maintain an alive-peer
set (expire after 35 s).

Sync loop: every 30 s, for each alive peer, pull deltas. Extend the existing
pull pattern to ALL replicated tables, not just messages (this fixes the
Phase 1 gap where gs_messages never left the node they were filed on):
- GET /sync/messages?since=<ts>          (X-Node-Auth as today)
- GET /sync/personnel?since=<ts>
- GET /sync/announcements?since=<ts>
- GET /sync/gs-messages?since=<ts>
- GET /sync/checkins?since=<ts>
Keep signature verification per record (existing pattern). Conflict rules:
- messages: CLAIMED beats NEW (existing precedence logic); if both CLAIMED,
  keep the earlier claim, retain claimed_by.
- personnel: REVOKED beats ACTIVE; otherwise newest updated_at wins.
- announcements, gs_messages, checkins: append-only by primary key.
Record every sync in the audit log as today (SYNC_START/OK/FAIL/REJECT).

Because peers are static IPs on an always-on interface, remove all nmcli
logic. The daemon must run fine when zero peers are in range (DTN normal
case) and converge when they appear (file 07 tests partition/heal).

## Task 2.4 Personnel + PIN auth (api.py additions)

Threat model note for the code comments: PINs are low entropy, so hash with
PBKDF2-SHA256 (>=200k iterations, 16-byte salt), rate-limit the login route
per IP and per personnel_id, and keep tokens short-lived.

Endpoints:
- POST /personnel (HQ role): create/update a record. Server computes salt,
  hash, signature. Returns the one-time plaintext PIN ONLY in this response
  (GCC displays it once; never stored in plaintext).
- GET /personnel (HQ role): list without hashes.
- POST /personnel/{id}/revoke (HQ role): status=REVOKED, updated_at=now.
- POST /auth/login (no key): {personnel_id, pin} -> verify against the
  LOCAL personnel table (which syncs fleet-wide) -> on success return
  {token, expires_at}. Token = base64(payload)+"."+HMAC(payload,
  NODE_SHARED_SECRET) where payload = {personnel_id, role:"RESCUE_TEAM",
  exp}. Stateless: ANY node can verify with the shared secret. TTL 24 h.
- Auth middleware: extend get_role() to accept header X-Session-Token; a
  valid, unexpired token whose personnel record exists and is ACTIVE maps to
  Role.RESCUE_TEAM. Revocation therefore propagates with DTN sync latency;
  document that latency as a known property.
- Keep X-API-Key working (GCC uses the HQ key; also the break-glass path if
  auth tables are empty).

## Task 2.5 Remaining endpoint work (api.py)

- /health (GET, public): real payload per design v3: node_id, gps
  {lat,lon,fix,sats,hdop}, battery {a_v,a_ma,b_v,b_ma}, uptime_s,
  clock_source, message counts by status, alive peers with last_seen,
  degraded nodes from node_health. Reads /run/rescue-mesh/aux_state.json.
- /announcements: GET (token or any role incl. USER? decide: rescue-scoped),
  POST (HQ role). Wire to the rescue app screen that already exists; confirm
  what that screen currently calls and align the contract.
- POST /checkin (no key, rate-limited like /message): {device_id, sos, points:
  [{lat,lon,accuracy,recorded_at}]} -> insert checkins; if sos true, ALSO
  create a normal message so it enters the rescue workflow.
- POST /message: accept the v3 fields (user_lat/user_lon...), stamp
  node_lat/node_lon from aux state, set time_source.
- Config: all constants (ports, intervals, limits) read from
  /etc/rescue-mesh/node.env via python-dotenv (progress report 4.3).
- Error handling pass per progress report 4.2: consistent JSON error bodies,
  explicit handling of DB lock/timeout, sync partial-failure isolation per
  table, and captive portal user-facing failure text.

## Acceptance for file 02

1. Two rebuilt nodes side by side: submit a victim message on A, claim it on
   B via the rescue app, file a gs uplink on B; within 60 s all three
   artifacts are identical on both nodes (verified with sqlite3 queries).
2. Personnel created via curl on A logs in on B with PIN only, receives a
   token, token works on A and B, revoke on A blocks new logins on B after
   the next sync.
3. Pull the aux module's USB cable: /health flips clock_source and stops
   updating GPS; plug back in: recovery without service restart.
4. Kill -9 the API mid-sync on one node: the other node's daemon logs
   SYNC_FAIL and continues; no crash, no duplicate rows after recovery.
5. Audit log contains login success/failure, revocation, and sync events.
