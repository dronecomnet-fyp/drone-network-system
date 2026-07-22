# 03 From Phase 1 to Phase 2

This is the "how and why" chapter. Phase 1 worked but had specific, documented
limitations. Phase 2 fixed each one, and the fixes are the reason the system
looks the way it does. Understanding this chapter means understanding the
design intent behind almost every later decision.

The authoritative source for these decisions is `Instructions_MD_files/00_MASTER_PLAN.md`
(decisions D1-D6) and `docs/CHANGES.md`. This chapter narrates them.

## What Phase 1 was

Phase 1 (kept as evidence in `local-server/` and `rescue-personnel-app/`)
proved the concept:

- A single Wi-Fi radio per Pi. A script, `switcher.py`, cycled that one radio
  between two modes: about 90 seconds as an access point (so users could
  connect), then about 40 seconds in client mode to scan for and sync with
  other nodes. Message propagation A to B to C was verified.
- A captive portal, a victim message form, and a claim workflow that
  propagated between nodes.
- A Flutter rescue app: requests, claim, HQ uplink, an announcements screen,
  and settings with an API key and a private key, pinning to a self-signed
  certificate for 10.42.0.1.
- A read-only web dashboard served by the Pi at `/gs` for the ground station.

It was a working prototype. But it carried limitations that the progress
report documented, and Phase 2 exists to remove them.

## The seven gaps, and how Phase 2 closed each

### Gap 1: users dropped off Wi-Fi during every sync (the big one)

**Phase 1:** one radio, time-sliced. During the ~40 second client/sync window,
the access point was gone, so every connected phone lost the network. Worse,
two nodes that both happened to be in their client window at the same moment
never met, so sync depended on lucky timing. This timing fragility was the
central weakness.

**Phase 2:** give each Pi a **second radio** and stop time-slicing entirely.
- `wlan0` (the Pi's onboard Wi-Fi) is a permanent 5 GHz access point,
  `RESCUE_x` at `10.42.0.1`. It never goes down, so users stay connected.
- `wlan1` (an AR9271 USB adapter) is a permanent 2.4 GHz **IBSS** (ad-hoc)
  cell at `10.99.0.x`. All nodes are always in the same cell, so any pair in
  range can sync at any moment.

**Why IBSS and not the Phase 1 approach, or something fancier?** This is master
plan decision **D2**, approved by the team on 2026-07-11:

- *Chosen:* all AR9271 adapters join one open IBSS cell with a fixed SSID
  (`RESCUE_DTN`), fixed frequency (2437 MHz, channel 6), and fixed BSSID
  (`02:12:34:56:78:9A`), with static IPs and the existing UDP-beacon + HTTP-pull
  sync on top. See `deploy/files/dtn-net-up.sh`.
- *Why:* no role switching at all; any pair in range syncs at any time; the
  sync loop stays simple; and the AR9271 (ath9k_htc driver) is one of the
  classic IBSS-capable adapters. It is also the cleanest delay-tolerant-network
  story for the thesis.
- *Rejected alternative (a):* keep the design-v3 idea of `wlan1` cycling
  between AP and station roles. It works, but two nodes both in the station
  phase never meet, so the Phase 1 timing fragility returns. Kept only as a
  documented fallback if IBSS misbehaves on the Bookworm kernel (`file 01`
  step 5).
- *Rejected alternative (b):* 802.11s mesh with BATMAN-adv. Real multi-hop
  routing, but overkill for three nodes, more failure modes, and it weakens the
  DTN store-and-forward narrative that is the point of the project.

The fixed BSSID matters: without it, IBSS cells can silently split into two
groups with the same SSID that never merge. Pinning the BSSID keeps one cell.

The catch this created: the Pi 4's **onboard** Wi-Fi (brcmfmac driver) cannot
do IBSS, and neither can an ESP32. So the mesh radio has to be the AR9271, and
the onboard radio has to be the AP. For DRONE_S this meant buying a *second*
AR9271 so it could be both a mesh node and talk to its flight controller
(chapter 11 tells that story).

### Gap 2: Bluetooth discovery never worked

**Phase 1:** the "drone nearby" feature used classic Bluetooth inquiry, not BLE
advertising, so phones never actually discovered a drone.

**Phase 2:** move BLE entirely to the ESP32-C3 aux module (master plan **D3**).
The ESP32 advertises a fixed 128-bit service UUID
(`2b57461c-1c04-49c4-944a-13643c1618da`) with the node id and SSID in the
payload; the emergency app filters scans by that UUID. This also removes the
Pi's Wi-Fi/Bluetooth coexistence problem. See `firmware/aux1/src/main.cpp` and
chapter 07. A real bench-level bug was found and fixed here: the UUID must be in
the advertising packet's service-UUID *list* (AD type 0x07), not only in the
service *data*, or scan filters do not match it.

### Gap 3: field reports never synced

**Phase 1:** rescuers' field reports (`gs_messages`) were stored only on the
node they were filed on and never reached the others.

**Phase 2:** `gs_messages` gained an HMAC signature column and joined the set of
tables that replicate fleet-wide. The Phase 1 sync logic (which handled only
messages) was generalised to all replicated tables. See
`backend/sync_engine.py` and chapter 04.

### Gap 4: no personnel authentication

**Phase 1:** anyone with the app could act; there was no notion of a specific
rescuer.

**Phase 2:** a personnel system. HQ issues a rescuer a one-time PIN; the
rescuer logs in and receives a session token that any node can verify offline
(chapter 05). Claims record the specific rescuer's identity. HQ operators log in
the same way. See `backend/api.py` (`/auth/login`), `backend/crypto_keys.py`
(token minting), and the login screens in the apps.

### Gap 5: no desktop operator app

**Phase 1:** a read-only web dashboard.

**Phase 2:** the GCC, a full Flutter desktop app (`gcc_app/`) with an offline
map, live feed, node health, personnel PIN issuance, announcements, drone
control, mission planning, live operations, and an AI planner. Chapters 08, 11,
12.

### Gap 6: no public victim app

**Phase 1:** victims used only the captive portal.

**Phase 2:** the emergency app (`emergency_app/`), a privacy-first public app
that logs a location ring buffer, discovers a nearby drone over BLE, and lets a
victim upload check-ins and an SOS. Chapter 10.

### Gap 7: weak security posture

Phase 1 had one shared secret used for everything and self-signed certificates
the apps accepted blindly. Phase 2 reworked this per the security architecture
(`file 09`), and this is important enough to be its own chapter (05). In short:

- One shared signing secret became **three purpose-separated keys** derived
  with HKDF (K_MSG for records, K_SYNC for inter-node auth and beacons, K_TOKEN
  for tokens), so one captured purpose does not compromise the others.
- "Accept any certificate for 10.42.0.1" (which is not pinning at all) became a
  **fleet certificate authority** issuing per-node certificates, with the apps
  embedding the CA and failing closed against evil-twin access points.
- The victim flow moved from certificate-warning-generating self-signed HTTPS
  to plain HTTP, because a victim hitting a certificate warning is a usability
  cost with no authentication benefit; victim-message integrity is protected by
  signing at ingest instead.
- Beacon replay was closed with a per-node monotonic counter.

## The rebuild, not the patch

One more decision shaped everything: Phase 2 is a **clean rebuild**, not an
in-place upgrade (master plan **D1**). The Phase 1 cards carried single-radio
switcher state, stale NetworkManager profiles, old iptables hooks, and
undocumented drift. A scripted rebuild from a blank SD card (chapter 14) gives
the reproducibility an examiner asks for, and the database schema changed
anyway (schema v3). The fleet is rebuilt together; there is no migration from
Phase 1 databases, which is a stated prototype-phase decision.

This is why the monorepo copies Phase 1 code in as evidence rather than editing
it: the honest paper trail is part of the deliverable.

## The one-line summary per gap

| Gap in Phase 1 | Phase 2 fix | Where |
|----------------|-------------|-------|
| Users drop off during sync | Second radio; always-on AP + always-on IBSS mesh | ch 04, `deploy/files/dtn-net-up.sh` |
| BLE never worked | BLE moved to the ESP32 with a fixed service UUID | ch 07, `firmware/aux1/src/main.cpp` |
| Field reports do not sync | `gs_messages` signed and replicated | ch 04, `backend/sync_engine.py` |
| No personnel auth | PIN login and offline-verifiable session tokens | ch 05, `backend/api.py` |
| No operator app | The GCC desktop app | ch 08, `gcc_app/` |
| No victim app | The emergency app | ch 10, `emergency_app/` |
| Weak security | HKDF key separation, fleet CA pinning, signed beacons | ch 05, `backend/crypto_keys.py` |
