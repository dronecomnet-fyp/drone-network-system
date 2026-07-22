# 04 The DTN Mesh Network

This chapter explains how the drones talk to phones and to each other, and how
messages travel across a network that is never guaranteed to be fully
connected. This is the heart of the system.

## Two radios, two jobs

Each node has two Wi-Fi interfaces doing two completely separate jobs. Keeping
them separate is what removed the Phase 1 time-slicing problem (chapter 03).

### wlan0: the user access point (5 GHz)

The Pi's onboard Wi-Fi is a permanent access point:

- SSID `RESCUE_x` (RESCUE_A / RESCUE_B / RESCUE_S), 5 GHz band, channel 36.
- The node is always `10.42.0.1` on this side, handing out DHCP leases in
  `10.42.0.0/24`.
- A captive portal (dnsmasq resolving every hostname to `10.42.0.1`, config in
  `deploy/files/portal.conf`) means any phone that joins sees the victim form.
- It is created by NetworkManager in "shared" mode by `deploy/setup_node.sh`.

Because it never cycles off, a connected phone stays connected. That is the
whole point.

### wlan1: the DTN mesh backbone (2.4 GHz, IBSS)

An AR9271 USB adapter (ath9k_htc driver) forms the drone-to-drone backbone:

- IBSS (ad-hoc) cell, always on. Parameters are fixed so every node joins the
  same cell: SSID `RESCUE_DTN`, frequency 2437 MHz (channel 6), BSSID
  `02:12:34:56:78:9A`. The fixed BSSID prevents IBSS split-cells (two groups
  with the same SSID that never merge).
- Static IPs `10.99.0.1/2/3` per node, from `/etc/rescue-mesh/dtn_ip`.
- Brought up by `deploy/files/dtn-net-up.sh`, run once at boot by the
  `dtn-net.service` systemd unit (a oneshot with retry, chapter 14).

The interface is marked unmanaged by NetworkManager (`deploy/files/unmanaged-dtn.conf`)
so NM does not fight the manual `iw` configuration.

**Why the onboard radio cannot be the mesh:** the Pi 4's brcmfmac driver does
not support IBSS. So the mesh must be the AR9271, and the AP must be the
onboard radio. This constraint drove several later decisions, especially for
DRONE_S (chapter 11).

## Addressing summary

| Interface | Role | Address | Who is on it |
|-----------|------|---------|--------------|
| wlan0 | 5 GHz user AP | 10.42.0.1 | victims, rescuers, the GCC |
| wlan1 | 2.4 GHz IBSS mesh | 10.99.0.x | the other nodes |

The GCC laptop joins whichever `RESCUE_x` is in range and talks to that one
node at `10.42.0.1:8443`. It does not see the mesh directly; its view of other
nodes is only as fresh as that node's last sync plus fallback beacons. This is
why every GCC screen shows data age.

## Delay-tolerant sync: beacons plus pull

The mesh is delay-tolerant: nodes may drift in and out of range, so there is no
assumption of a permanent link. Two mechanisms make it work, both in
`backend/sync_daemon.py` and `backend/sync_engine.py`.

### Presence beacons (who is out there)

Every `BEACON_INTERVAL` (10 s) each node broadcasts a small signed UDP beacon
to `10.99.0.255:48555` (configurable; unicast targets are also supported for
testing). The beacon carries the node id, its API port, its per-table row
counts, and a monotonic counter.

- **Signed** with K_SYNC, so a receiver knows it came from a real fleet node.
- **Replay-protected**: each node persists the last counter it accepted from
  each peer and rejects any beacon whose counter does not increase. This is a
  counter, not a clock, because a node may be running on relative time before
  it gets a GPS fix. This closes the Phase 1 beacon-replay gap (`file 09` F6).
- A peer is considered alive if a valid beacon arrived within `PEER_EXPIRY`
  (35 s).

`sync_daemon.build_beacon()` builds it; `parse_and_accept_beacon()` verifies
and records it.

### Pull sync (get the new rows)

Every `SYNC_INTERVAL` (30 s) a node pulls new rows from each alive peer. This
is a pull, not a push, matching the Phase 1 trust direction.

For each replicated table and each peer, the node:

1. Looks up its per-peer, per-table cursor (`get_sync_cursor`): the last
   `local_ts` it has already pulled from that peer.
2. Requests `GET https://<peer>:8443/sync/<table>?since=<cursor>` with the
   `X-Node-Auth` header (a K_SYNC value proving fleet membership).
3. For each returned row, verifies the row's HMAC signature with K_MSG. A row
   that fails verification is rejected and logged; a forged plea for help never
   enters the database.
4. Applies the table's conflict rule (below), stamping accepted rows with a
   fresh local `local_ts` so they propagate onward to the next peer this node
   meets. That onward propagation is what makes it store-and-forward.

`SYNC_PATHS` maps a table to its wire path; `INGEST_FN` maps a table to its
ingest function; `sync_with_peer()` drives the loop.

### The two timestamps (a common point of confusion)

Every replicated row has two time fields, and they mean different things:

- `updated_at` (or `recorded_at`/`timestamp`): the **signed, origin** time,
  set by the node that created the row. It travels unchanged and is part of the
  signature. Conflict resolution compares this.
- `local_ts`: the **per-hop cursor** stamp. Each node sets it to "now" when it
  stores a row, whether it created the row or pulled it. The sync cursor
  advances in the peer's `local_ts` space. It is not signed.

This separation is what lets a row propagate multiple hops while conflict rules
still compare the true origin time.

## The replicated tables and their conflict rules

Defined in `backend/models.py` (`REPLICATED_TABLES`) and enforced in
`backend/sync_engine.py`:

| Table | Primary key | Conflict rule |
|-------|-------------|---------------|
| `messages` | `msg_id` | CLAIMED beats NEW; if both CLAIMED, the earlier `claimed_at` wins and its claimer is kept |
| `personnel` | `personnel_id` | REVOKED beats ACTIVE; otherwise newest `updated_at` wins |
| `personnel_locations` | `personnel_id` | newest `updated_at` wins (latest position per rescuer) |
| `announcements` | `id` | append-only by primary key |
| `gs_messages` | `id` | append-only by primary key |
| `checkins` | `id` | append-only by primary key |

"Append-only by primary key" means: if the id already exists, keep what we
have; otherwise insert. "Newest wins" and "CLAIMED beats NEW" implement the
operational logic (a claimed message must not be un-claimed by a stale copy; a
revoked credential must not be un-revoked). Every ingest verifies the signature
first; failure isolation is per-table, so one bad table does not stop the
others.

## When a node dies: LoRa fallback

If a node's Pi crashes, its mesh presence disappears. The aux module (chapter
07) notices the Pi has gone quiet and starts beaconing the node's last known
position over **LoRa** (915 MHz, long range, low bandwidth). A neighbouring
node's aux module receives it and forwards it to its Pi, which records the
sender as a **degraded node**. The GCC then shows that node as DEGRADED at its
last position instead of it simply vanishing. This is the safety net for a
dead Pi, and it is why the fleet manager can show a drone as FALLBACK rather
than LOST (chapter 11).

## The documented fallback if IBSS fails

If IBSS turns out to be unreliable on a particular kernel, the design has a
recorded fallback: the Phase 1 style of cycling `wlan1` between AP and station
roles (`file 01` step 5). It is not built preemptively, on purpose; building
an unused fallback is waste. It is documented so the next team knows the escape
hatch exists and why it is the second choice (it reintroduces timing
fragility).

## Where the code lives

- Interface bring-up: `deploy/files/dtn-net-up.sh`, `deploy/setup_node.sh`
- Captive portal: `deploy/files/portal.conf`
- Beacons and sync loop: `backend/sync_daemon.py`
- Record ingest and conflict rules: `backend/sync_engine.py`
- Table definitions and signing: `backend/models.py`
- Tunable intervals and addresses: `backend/config.py`
- Two-node sync test: `backend/tests/test_sync_conflicts.py`,
  `tools/` local two-node test
