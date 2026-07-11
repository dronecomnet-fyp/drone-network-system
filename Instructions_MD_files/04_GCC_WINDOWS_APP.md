# 04 GROUND CONTROL CENTER: FLUTTER WINDOWS DESKTOP APP

Goal: replace the read-only /gs web dashboard with a dedicated Windows
desktop application (new repo folder `gcc_app/`, Flutter with the windows
target enabled). Master plan D4 records the framework decision and rejected
alternatives; restate them in the app README for the report.

Connectivity model (state this in the UI, examiners will ask): the GCC
laptop joins the WiFi of whichever drone is in range and talks to
https://10.42.0.1:8443 with the HQ key. Its view of OTHER drones is only as
fresh as DTN sync plus fallback beacons. The Nodes screen must show a
last-updated age per node instead of pretending everything is live.

## Screens and features

1. Operations Map (home)
   - flutter_map with OFFLINE tiles. No internet exists at a deployment, so
     bundle tiles: provide a documented pre-mission step that downloads the
     target region into an MBTiles file (or a tile cache directory) and a
     Settings field to load it. This is a headline thesis feature; do not
     ship an online-only map.
   - Layers: drone nodes (from /health, degraded nodes greyed with last-known
     position from fallback beacons), victim messages with user_lat/user_lon,
     checkins heat/dots from the emergency app data, personnel-filed gs
     message locations.
   - PLANNING mode: drop named planning markers ("place drone here"), draw
     coverage circles (configurable radius), save/load an operation plan as a
     local JSON file. Planning markers are advisory; they do NOT command the
     drone. Optional later: POST the plan to nodes so it syncs, only if time
     permits.

2. Live Feed: all victim messages, filter/search (progress report wishlist),
   claim/unclaim visibility, decryption of E2E payloads if the HQ operator
   pastes the rescue private key (reuse the logic pattern from the mobile
   app's message_crypto_service).

3. Nodes: per-node health cards from /health: GPS, both battery voltages and
   currents, uptime, clock_source, message counts, peer last-seen table,
   DEGRADED banner sourced from fallback beacons. 5 s polling like today.

4. Personnel: the new capability.
   - Create personnel (name, role, expiry) -> backend returns the one-time
     PIN -> display large with a copy button and a "PIN is shown only once"
     notice.
   - List with status, revoke button (confirm dialog), and a visible caveat:
     revocation reaches other drones at DTN sync speed.

5. Announcements: compose + priority -> POST /announcements; list existing.

6. Drone Control (SYSTEM DRONE ONLY; hide or disable the tab when the
   selected node is a volunteer drone; enforce with a per-node config flag).
   See section below.

7. Settings: base URL, HQ key, offline map file, MAVLink target (with the
   DIRECT and MESH RELAY presets from the Drone Control section), TLS trust
   for the self-signed cert (pin by IP exactly like the mobile app's
   _buildClient), theme.

8. Packaging: the GCC is delivered to the ground laptop as an INSTALLED
   Windows app, not a dev build. Produce a versioned release (installer or
   portable zip of the Flutter Windows build) with install steps and a
   release log in docs/RELEASES.md.

Shared code: extract Message/GSMessage/health models and the API client into
a small shared Dart package used by gcc_app, the rescue app, and the
emergency app, so contracts stay in one place.

## Drone Control tab: staged, safety-gated

Stage 0 (hardware identification, MANDATORY before any code):
- Connect the system drone's Revo Mini over USB, props OFF. Try, in order:
  Mission Planner (ArduPilot/MAVLink), Betaflight Configurator (MSP), LibrePilot
  GCS (UAVTalk). Record which one talks. Separately, power the drone's
  ESP32-WROOM bridge and identify its firmware (serial banner at common baud
  rates; DroneBridge exposes a WiFi AP and a web UI if present). The
  Drone_detailed_Hardware_Doc explicitly says protocol is unconfirmed and
  that a Mission Planner screenshot suggested MAVLink was being tested.
- Write the findings into gcc_app/DRONE_LINK.md before proceeding.

Stage 1 (telemetry, the MVP for the thesis demo):
- Target stack: ArduPilot (ArduCopter) on the Revo Mini. ArduPilot's official
  docs state Revolution and RevoMini are supported in stable releases
  (ardupilot.org/copter/docs/common-openpilot-revo-mini.html). Confidence:
  High. Flashing requires DFU-mode pad shorting per that page; note also from
  the ArduPilot wiki that RC input on this board requires PPM or SBus, not
  per-channel PWM (verify the drone's receiver type during Stage 0).
- Link (updated per file 08): MAVLink UDP to the mavlink-router service on
  the Pi mounted on the system drone. Two paths, selectable in GCC
  Settings as a MAVLink target with presets: DIRECT (laptop on RESCUE_S,
  target 10.42.0.1:14550) and MESH RELAY (laptop on RESCUE_A/B, target
  10.99.0.3:14550, routed by the volunteer Pi per file 08). The drone's
  own ESP32 bridge is demoted to an optional backup link; if kept, fix its
  WiFi channel per master plan R2.
- GCC implements: heartbeat, attitude, GPS, battery, mode, arming state.
  Use the dart_mavlink package if it proves adequate at implementation time;
  otherwise embed a small local bridge process and keep the UI in Flutter.
  Decide during implementation and record the reason.

Stage 2 (guided reposition, STRETCH: attempt only after Stage 1 is stable
and the safety gates pass):
- "Send drone to marker": requires GUIDED mode, GPS 3D fix, EKF happy,
  geofence configured, and an explicit confirm dialog showing distance and
  altitude. All command buttons stay disabled unless the MAVLink heartbeat
  is fresher than 2 seconds; over the mesh relay this enforces the
  live-link-only rule from file 08 automatically. Buttons: Arm (double confirm), Takeoff to configured altitude,
  Goto marker, RTL, Land, and a always-visible DISARM/kill.
- Safety gates before ANY armed test with props: bench test props-off; all
  ArduPilot arming checks left ON; RC failsafe = RTL, GCS-loss behavior
  configured; geofence radius and altitude set; a human pilot with the RC
  transmitter as override at all times; supervisor-approved open test area.
  Put this checklist in the UI as a pre-arm screen the operator must tick.
- If Stage 0 reveals Betaflight and reflashing is refused/blocked: document
  honestly that GCC control is telemetry-plus-manual-flight for this drone,
  because Betaflight has no GPS waypoint navigation. Do not fake it.

## Out of scope for this file

Controlling the two volunteer drones (project scope), multi-drone swarm
coordination, video streaming.

## Acceptance for file 04

1. GCC on a Windows laptop joined to RESCUE_A shows live feed, nodes, and
   the offline map with real message pins, with WiFi to the internet OFF.
2. Personnel round trip: create in GCC -> PIN login succeeds in the rescue
   app on a different drone (proves DTN carry of personnel records).
3. Announcement composed in GCC appears in the rescue app.
4. A planning marker set, saved, app restarted, plan reloads.
5. Stage 1: live MAVLink telemetry from the bench drone (props off) rendered
   in the Drone Control tab, and DRONE_LINK.md filled in.
6. Stage 2 only if attempted: logged supervised field test with the pre-arm
   checklist screenshot for the report.
