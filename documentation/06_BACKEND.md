# 06 The Node Backend

The backend is the Python software every drone node runs. It is a FastAPI
application (two of them, actually), a SQLite database, and two background
daemons. It is specified by `Instructions_MD_files/02_BACKEND_V2_DTN_AUTH.md`
("file 02") and the security parts of file 09. All of it lives in `backend/`.

## The two apps

The node runs two separate ASGI applications, for the security reason in
chapter 05:

- `backend/http_app.py`: the **victim plane**. Plain HTTP on port 80 (the
  service is granted `CAP_NET_BIND_SERVICE` so the non-root service user can
  bind the low port). Serves the captive-portal probes, the victim message form,
  and
  `POST /message` and `POST /checkin`. No authentication by design.
- `backend/api.py`: the **authenticated plane**. HTTPS on port 8443 with the
  fleet-CA node certificate. Every rescuer, HQ, and sync endpoint.

They share the same `models.py` database but are wired separately so the open
plane can never serve an authenticated route.

## The database: schema v3

`backend/models.py` owns the SQLite schema and every read/write. `init_db()`
creates all tables with `CREATE TABLE IF NOT EXISTS`, so starting an updated
node simply adds any new table with no migration and no data loss (this is how
the rescuer-location table was rolled out; chapter 12).

The tables that replicate over the mesh are registered in one place,
`REPLICATED_TABLES`, which drives index creation, the `since` sync query,
row counts, and the sync loop. To add a synced table you touch that dict, add a
canonical payload function and register it in `_PAYLOAD_FN`, add the
`CREATE TABLE` (with `signature` and `local_ts` columns), and register a sync
path and ingest function in `sync_engine.py` (chapter 04 lists the exact
places).

Key tables:

- `messages`: victim messages, schema v3 (msg_id, content, user_lat/lon,
  node_lat/lon, timestamp ISO 8601 UTC, time_source gps|relative, node_id,
  status NEW|CLAIMED, claimed_by, claimed_at, synced_from, plus security
  columns). `time_source` records whether the origin node's clock was
  GPS-synced; the apps show relative-time timestamps with a "~" hint.
- `personnel`: rescuers and HQ operators (pin_salt, pin_hash pbkdf2_sha256,
  pin_iterations, role RESCUE_TEAM|HQ, status ACTIVE|REVOKED, updated_at,
  signature).
- `personnel_locations`: latest position per rescuer (chapter 12).
- `announcements`, `checkins`, `gs_messages`: as their names suggest.
- `node_health`: local telemetry snapshots (not replicated; latest-per-node is
  computed at read time).
- `sync_cursor` and a peer-counter table: sync bookkeeping (chapter 04).

Every replicated write is signed at ingest with K_MSG (`sign_record`); every
sync read verifies (`verify_record`).

## The endpoints

On the victim plane (`http_app.py`, port 80):

- The captive-portal probe URLs and the victim HTML form.
- `POST /message`: a victim message, validated and size-capped, rate-limited
  per IP and against a global cap, signed and stored.
- `POST /checkin`: an emergency-app check-in; `sos=true` also creates a normal
  message so it appears in the rescue feed.

On the authenticated plane (`api.py`, port 8443):

- `POST /auth/login`: PIN login, returns a session token (chapter 05).
- `GET /messages`, `POST /messages/{id}/claim`: the rescue feed and claiming.
- `GET/POST /announcements`: rescue-scoped operational notices.
- `POST /personnel` (HQ), `GET /personnel` (HQ, no hashes),
  `POST /personnel/{id}/revoke` (HQ): personnel lifecycle.
- `GET /checkins`, `GET /gs-messages`, `POST /gs-uplink`: check-ins and field
  reports.
- `POST /personnel-location`, `GET /personnel-locations`: rescuer location
  heartbeat (chapter 12).
- `GET /health`: a real status payload (aux GPS/battery, uptime, message and
  table counts, alive peers, degraded nodes). Public, so the GCC can watch a
  node come into range before logging in.
- `GET /sync/<table>?since=`: the pull-sync endpoints, restricted to the
  SYNC_NODE role (K_SYNC). Registered from one factory, `_sync_endpoint`.

Authentication is resolved by `get_auth`: a valid `X-Session-Token` (verified
against K_TOKEN, with the personnel record re-checked ACTIVE) maps to that
person's role; the break-glass `X-API-Key` still works; `require_roles({...})`
is the per-endpoint guard. See chapter 05 for the 401-vs-403 rule the apps
depend on.

## The background daemons

Two long-running processes accompany the API (chapter 14 wires them as systemd
services):

### The sync daemon (`backend/sync_daemon.py`)

Broadcasts a signed presence beacon every 10 seconds and pulls new rows from
every alive peer every 30 seconds. This is the DTN engine; chapter 04 covers it
in full. It runs fine with zero peers (a lone node just beacons and waits).

### The aux bridge (`backend/aux_bridge.py`)

Talks to the ESP32-C3 aux module over a serial line (newline-delimited JSON). It:

- caches the latest GPS and battery readings and writes them to
  `/run/rescue-mesh/aux_state.json` (read by `/health` and stamped onto new
  victim messages);
- sets the Pi clock once at startup and then hourly from GPS time, through a
  narrow sudoers rule that permits only `date -u -s` (chapter 14), audit-logging
  the old and new time;
- records LoRa fallback receptions as degraded-node health, so a dead peer
  shows up (chapter 04);
- pushes new-message summaries and other events down to the aux module.

It exits cleanly if no serial device is configured, which is the case on a node
without an aux module (currently DRONE_S, whose GPS comes from its flight
controller instead; chapter 11).

## Configuration, not constants

Everything a node needs to know about itself lives in `/etc/rescue-mesh/node.env`,
generated by the setup script from the per-node conf file. `backend/config.py`
loads it (tolerating an unreadable file, since systemd also populates the
environment) and exposes node id, SSIDs, IPs, ports, intervals, and rate limits.
There are no hard-coded node identities in the code. This is a project ground
rule: config over constants.

## Running it locally

You do not need hardware to run and test the backend. From `backend/` with the
virtualenv:

```
.venv/bin/python -m pytest tests/ -q
```

The test suite runs both apps against a temporary database with a test
environment, covering the auth lifecycle, rate limits, token forgery/expiry,
the sync conflict rules, and beacon replay. Chapter 15 has the details.

## Where the code lives

```
backend/
  http_app.py      victim plane (port 80)
  api.py           authenticated plane (port 8443)
  models.py        schema v3, all DB access, record signing
  sync_engine.py   record ingest + conflict rules
  sync_daemon.py   presence beacons + pull loop
  aux_bridge.py    serial link to the ESP32 aux module
  crypto_keys.py   HKDF keys + token mint/verify
  ratelimit.py     sliding-window + global limiters
  audit.py         audit logger
  aux_state.py     the /run aux state file helpers
  config.py        loads /etc/rescue-mesh/node.env
  archived/        Phase 1 switcher.py and ble_discovery.py, retired
  tests/           pytest suite
```
