# 00 MASTER PLAN - Phase 2: Dual Radio, Aux Module, GCC Desktop App, Personnel Auth, Emergency App

Read this file first. Files 01 to 07 are the work packages, in execution order.
Each work package is written so Claude Code can implement it directly against the
existing repository. Authoritative background documents are in the project files:
communication_module_design_v3, Progress_Report, com_module_battery_capacity_decision,
Drone_detailed_Hardware_Doc.

## 1. Fleet scope (do not violate)

- 2 communication modules (DRONE_A, DRONE_B) ride as payloads on
  volunteer-owned DIY drones. For these two nodes the project builds the
  COMMUNICATION MODULE ONLY. No flight controller, ESC, motor, or airframe
  work for these two.
- 1 system-owned drone (AeroSync 5 type: Revo Mini FC, ESP32-WROOM WiFi-serial
  bridge, RS2205 motors, 40A ESCs). Flight control integration applies to this
  drone only. The THIRD Raspberry Pi (originally planned as a third comm
  module) is mounted on this drone as node DRONE_S: a full mesh node plus
  MAVLink gateway, so the GCC can control the drone directly or relayed
  through a volunteer drone's module. Work package: file 08. DRONE_S flies
  without an aux module by default (only two aux sets exist).

## 2. Where the project stands today (verified from repo files)

Working (Phase 1, per Progress_Report):
- FastAPI backend: api.py (HTTPS 8443, role keys RESCUE_TEAM/HQ/SYNC_NODE),
  http_app.py (captive portal probes), models.py (SQLite, WAL, HMAC message
  signatures), sync_engine.py (HTTP pull sync with signature verification).
- Single-radio DTN: switcher.py cycles wlan0 between AP mode (90 s) and
  client scan/sync mode (40 s). Message propagation A -> B -> C verified.
- Captive portal, claim workflow, claim propagation: verified working.
- Rescue app (Flutter): requests, claim, HQ uplink, announcements screen,
  settings with API key + private key, self-signed cert pinning to 10.42.0.1.
- Ground station: read-only web dashboard served by the Pi at /gs.
- Batteries decided and quoted: Battery A 2S 2400 mAh, Battery B 1S 2400 mAh
  (see battery capacity decision doc, calculations already recorded).

Broken or missing:
- ble_discovery.py uses `bluetoothctl discoverable on`. That makes the Pi
  visible over CLASSIC Bluetooth inquiry, not BLE advertising. Phones scanning
  for BLE advertisements do not see it. This is why it "totally failed".
  Design v3 already moved BLE to the ESP32-C3, which is the correct fix.
- No dual-radio operation yet: users lose connectivity during every sync cycle.
- ESP32-C3 aux module: only three separate test sketches exist
  (com_module_lora, com_module_gps, com_module_ina3221). No unified firmware,
  no serial protocol to the Pi, no fallback mode, no BLE advertising.
- gs_messages (field reports) DO NOT sync between nodes. Only the messages
  table syncs. A GCC connected to drone A cannot see reports filed via drone B.
- The announcements screen exists in the rescue app but api.py has no
  /announcements endpoints. Verify and implement backend side.
- No personnel management, no PIN login, no session tokens.
- No Windows ground control app, no drone control, no operation planning.
- No public emergency app.
- /health returns only {"status":"ok"}; design v3 requires GPS, battery,
  uptime, clock source, message counts.
- Message schema in models.py is the OLD schema. Design v3 defines a new one
  (user_lat, user_lon, node_lat, node_lon, time_source, node_id, claimed_by,
  synced_from).

## 3. Target architecture for this phase

Per node (communication module):

```
                    5 GHz AP (onboard Pi WiFi, always on)
  Victims/Rescue -->  captive portal :80 -> HTTPS app :8443
                          |
  Raspberry Pi 4B: api + sync daemon + aux-bridge daemon (systemd)
                          |  USB serial JSON (115200)
  XIAO ESP32-C3 aux: GPS + INA3221 + LoRa 915 + BLE advertising
                          |
  AR9271 USB (wlan1): 2.4 GHz DTN backbone, ALWAYS ON, IBSS ad-hoc cell
  10.99.0.x static, UDP presence beacons + HTTP pull sync
```

Ground side:
- GCC: Flutter WINDOWS DESKTOP app, delivered as an installable Windows
  build for the ground laptop. Connects to whichever drone AP is in range.
  Operation planning on an OFFLINE map, node health, all messages,
  personnel + PIN issuance, announcements, and (system drone only) flight
  telemetry/control via MAVLink to the Pi mounted on the system drone,
  either directly on RESCUE_S or relayed across the DTN mesh (file 08).
  The drone's own ESP32 WiFi bridge remains only as an optional backup link.
- Rescue app: adds PIN login (personnel_id + PIN -> signed session token,
  verifiable offline by ANY node).
- Emergency app (new, public): background location log 2x/day stored on the
  phone, BLE detection of a drone -> high-priority notification -> user taps
  -> app helps join drone WiFi and uploads stored locations / SOS.

## 4. Key decisions (chosen / why / alternatives / why rejected)

D1. Rebuild the Pis fresh instead of patching in place.
- Chosen: image-backup each current SD card, then flash fresh Raspberry Pi OS
  Lite 64-bit (Bookworm) and run a scripted setup (file 01).
- Why: the current cards carry single-radio switcher state, stale
  NetworkManager profiles, old iptables hooks, and undocumented drift. A
  scripted rebuild gives the reproducibility examiners ask about, and the DB
  schema changes anyway (design v3 schema).
- Alternatives: (a) in-place upgrade: rejected, high risk of hidden state and
  impossible to document honestly; (b) keep one node old for comparison:
  rejected, sync protocol changes make mixed fleets incompatible.
- Old data: export drone_mesh.db and audit.log before wiping if the team wants
  test data for the report. Keep ONE original card unmodified as rollback
  until file 07 tests pass.

D2. DTN backbone on wlan1 uses IBSS (ad-hoc) with static IPs, not AP/client
role cycling.
- Chosen: all three AR9271 adapters join one open IBSS cell (fixed SSID,
  fixed channel, fixed BSSID), nodes at 10.99.0.1/2/3, UDP presence beacons,
  HTTP pull sync (reusing the existing sync logic and HMAC).
- Why: no role switching at all, any pair in range can sync at any time,
  simplest sync loop, and the AR9271/ath9k_htc driver is one of the classic
  IBSS-capable adapters. This is also the cleanest DTN story for the thesis.
- Alternatives: (a) design v3 wording (wlan1 cycles AP <-> station): works but
  two nodes both in station phase never meet, and the timing fragility from
  Phase 1 returns; keep as FALLBACK if IBSS misbehaves on the Bookworm kernel.
  (b) 802.11s mesh + BATMAN-adv: real routing, but overkill for 3 nodes, more
  failure modes, and it weakens the DTN store-and-forward narrative.
- STATUS: APPROVED (team decision, 2026-07-11). Rule 9 disclosure: this
  supersedes the station-cycling wording in design v3 section 3.2 layer 2;
  write the change, the reasons, and the rejected alternatives into design
  doc v4 so the examined paper trail matches the implementation. Technical
  fallback (only if IBSS fails T2/T3): file 01 step 5.

D3. BLE advertising moves entirely to the ESP32-C3; Pi Bluetooth is disabled.
- Chosen: ESP32-C3 advertises a fixed custom 128-bit service UUID with service
  data payload {node_id, ssid}. Phones filter scans by that UUID.
- Why: matches design v3, removes the Pi WiFi/BT coexistence question raised
  in the progress report, and the old Pi approach was never real BLE
  advertising anyway.
- Alternatives: (a) fix BLE on the Pi via BlueZ D-Bus LEAdvertisingManager1:
  technically possible but shares the Pi combo chip antenna with the 5 GHz AP
  and re-opens the feasibility question; rejected. (b) iBeacon format:
  optional ADDITION later for faster iOS wake, not the primary mechanism.

D4. GCC is a Flutter Windows desktop app.
- Chosen: Flutter (Windows target).
- Why: the team already ships a Flutter app; Dart models and the API client
  can be shared; one language across both apps; flutter_map supports offline
  tiles which the GCC needs (no internet at a disaster site).
- Alternatives: Electron (heavy, new JS stack, no code sharing), Tauri (Rust
  learning curve), .NET WPF/WinUI (Windows-native but a new language and zero
  sharing with the mobile apps), PyQt (shares Python with backend but slow UI
  iteration and still no sharing with the apps). All rejected on team-skill
  and code-sharing grounds.

D5. Drone control is staged, and gated on confirming the FC firmware.
- Stage 0 (mandatory): identify what is actually flashed on the system
  drone's Revo Mini and its ESP32 bridge. The hardware doc explicitly says
  this is unconfirmed (LibrePilot vs Betaflight/iNav vs ArduPilot/MAVLink).
- Recommended target: ArduPilot (ArduCopter) on the Revo Mini + MAVLink over
  the ESP32 WiFi bridge. ArduPilot's official documentation states it
  supports Revolution and RevoMini in stable releases
  (https://ardupilot.org/copter/docs/common-openpilot-revo-mini.html).
  Confidence: High (official docs). ArduPilot gives GUIDED "fly to point",
  RTL, geofence, failsafes, and a standard protocol the GCC can speak.
- Alternatives: Betaflight (no GPS waypoint navigation, rejected for this
  feature), iNav (has nav, but MSP command integration into a custom GCS is
  harder than MAVLink; acceptable fallback), stock LibrePilot (aging, no
  simple guided API; rejected).
- MVP vs stretch (be honest with the supervisor): MVP = live telemetry in the
  GCC + planning markers + pilot flies manually. Stretch = GCC-commanded
  guided reposition with geofence and confirm dialog. A bench-built 5 inch
  quad needs tuning and failsafe work before any autonomous command; file 04
  contains the safety gates.

D6. Personnel auth is decentralized: records sync over DTN, tokens are
HMAC-signed so ANY node can verify them offline. Details in files 02 and 05.

D7. The third Pi flies on the system drone as node DRONE_S (full node plus
MAVLink gateway).
- Chosen: same node image/software as A and B, plus a mavlink-router service
  wired to the flight controller. GCC controls the drone directly on
  RESCUE_S or relayed across the IBSS mesh via a volunteer drone's module.
- Why: the drone's own ESP32-WROOM bridge is 2.4 GHz only (cannot join the
  5 GHz user AP) and ESP32s do not support IBSS at all (station, softAP,
  ESP-NOW only), so without a Pi aboard the system drone can never enter
  the mesh. This configuration is the only one that satisfies "control the
  system drone through a volunteer drone's module", and it restores a third
  DTN node for free.
- Alternatives: direct ESP32-bridge link only (range-limited, laptop must
  hop networks; kept as backup), third Pi as a ground node (leaves the
  control problem unsolved), re-banding a module's user AP to 2.4 GHz so
  the ESP32 could join (creates R2 interference; rejected).
- Hard rule: flight commands only over a live link, never store-and-forward.
  Details, hardware checklist, and lift-test gate: file 08.

D8. Security architecture is threat-model driven, per file 09: keep role
separation, record HMAC signing, rate limits, audit log, and the PIN/token
design; fix fake cert pinning, single-secret-for-everything, the victim
cert-warning flow, committed secrets, beacon replay, and the open MAVLink
port; demote inter-node mTLS and fleet-keypair E2E to documented options,
off by default, with reasons recorded.

## 5. Execution order

1. File 01: Pi rebuild + dual radio bring-up (per node). Blocks everything.
2. File 02: backend v2 (schema v3, always-on sync daemon, personnel/auth,
   announcements, checkins, health, aux-bridge daemon). Depends on 01.
3. File 03: ESP32-C3 unified firmware. Can start in parallel with 01/02;
   integration test needs 02's aux-bridge.
4. File 04: GCC Windows app. Needs 02's API. Drone-control tab needs D5
   Stage 0 done on the real drone.
5. File 05: rescue app update (PIN login). Needs 02 auth endpoints.
6. File 06: emergency public app. Needs 03 BLE advertising + 02 /checkin.
7. File 08: system drone relay node. Its Pi setup runs together with 01
   (same image, drone_s.conf); the MAVLink relay part needs 02 and 04
   Stage 1, and can run in parallel with 05/06.
8. File 07: integration test plan and examiner demo script.
9. Documentation: update the design document to v4 (docx, plain formatting per
   project rules) reflecting D2 through D8, the GCC, the emergency app, and
   the DRONE_S relay node. This is a supervisor-facing deliverable; produce
   it AFTER the architecture stops moving, before the next review.

Cross-cutting: file 09 (security architecture) is not a build step of its
own; apply its tasks inside 01, 02, 04, 05, and 08 per its section 4, and
its acceptance drills join file 07 as T9.

## 6. Cross-cutting risks and open items (carry into every work package)

R1. LoRa 915 MHz legality in Sri Lanka is NOT confirmed. The Things Network's
country table lists no frequency plan for Sri Lanka, and 915 MHz sits at the
edge of the 900 MHz mobile uplink band used by local operators. Design v3
already flags "regional frequency regulations should be verified".
Actions: (a) check the TRCSL National Frequency Allocation Table
(trc.gov.lk/content/files/spectrum/FINALRadioFrequencySL.pdf) and ask the
department to confirm or obtain experimental clearance through the
university; (b) until cleared, bench-test at minimum TX power (LoRa.setTxPower
lowest setting) for short durations only; (c) note the RFM95's radio IC
family is typically tunable across the high band in firmware, so retuning to
another sub-GHz frequency may be possible with the SAME module if TRCSL
requires it. Confidence on retune claim: Moderate (depends on module variant,
verify against the HopeRF RFM95 datasheet before relying on it). Record the
outcome in the thesis as a regulatory-compliance section; examiners reward
this, they punish silence on it.

R2. 2.4 GHz congestion on the airframe: AR9271 DTN link, ESP32-C3 BLE, and
(system drone only) the drone's own ESP32-WROOM control link all live in
2.4 GHz. Fix the DTN WiFi channel (file 01 uses channel 6) and the drone
bridge channel (file 04) at opposite ends of the band, and document the
channel plan in design v4. BLE hops adaptively and needs no static channel.

R3. 5 GHz user AP excludes phones that only support 2.4 GHz. This is a
deliberate tradeoff (keeps the user AP off the DTN band). Document it as a
limitation; do NOT silently move the user AP to 2.4 GHz. Also confirm outdoor
5 GHz rules in TRCSL's outdoor WLAN guideline
(trc.gov.lk/content/files/spectrum/RegulatoryGuidelinesForOutdorWLAN.pdf) and
set the Pi WiFi country code to LK (file 01).

R4. Phones cannot be auto-opened by BLE. Android and iOS do not allow an app
to bring itself to the foreground from a background scan. The achievable
behavior is: background scan detects the drone -> high-priority notification
-> user taps -> app opens. Say this plainly to the panel; file 06 specifies
the exact mechanism per platform.

R5. Clock: the Pi has no RTC and no NTP in the field. Message timestamps and
the health log depend on the GPS time feed from the aux module (design v3
section 3.3). File 02 implements it; file 07 tests boot-before-fix behavior.

R6. Schema break: v3 schema is not compatible with Phase 1 databases. The
fleet is rebuilt together (D1), so no live migration is written. State this
in the thesis: prototype-phase decision, fresh deployment.

R7. DRONE_S payload and control latency. A Pi 4 plus Battery A plus the
AR9271 is real mass on a 5 inch class quad; file 08's lift test is a hard
gate before committing to the onboard-battery power design, with a BEC
fallback if the mass fails. And the relay path only exists while both
drones are inside 2.4 GHz range of each other: commands are gated on a
fresh MAVLink heartbeat, the FC's GCS-loss failsafe covers drops, and
manual stick flying over the relay is prohibited (RC pilot stays override).
