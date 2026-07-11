# gcc_app: Rescue Mesh Ground Control Center (file 04)

Windows desktop application for the ground laptop, replacing the Phase 1
read-only /gs web dashboard. The macOS target exists for development only;
the deliverable is an installed Windows build (docs/RELEASES.md).

## Connectivity model (say this to examiners)

The GCC laptop joins the WiFi of whichever drone is in range and talks to
that ONE node at https://10.42.0.1:8443 over the pinned fleet CA. Its
view of OTHER drones is only as fresh as DTN sync plus LoRa fallback
beacons, so every dataset in the UI carries a last-updated age; nothing
pretends to be live.

## Framework decision (master plan D4, restated for the report)

Chosen: Flutter with the Windows desktop target.
Why: the team already ships a Flutter app; the Dart models and API client
are shared through the rescue_mesh_shared package (one contract for GCC,
rescue app, and emergency app); one language across all apps; flutter_map
supports offline tiles, which is a hard requirement (no internet at a
disaster site).
Alternatives rejected: Electron (heavy, new JS stack, no code sharing),
Tauri (Rust learning curve), .NET WPF/WinUI (Windows-native but a new
language and zero sharing with the mobile apps), PyQt (shares Python with
the backend but slow UI iteration and still no sharing with the apps).
All rejected on team-skill and code-sharing grounds.

## Screens

| Tab | What |
|-----|------|
| Map | Offline MBTiles map (Settings loads the region file); layers for victim messages (NEW red / CLAIMED green), emergency-app checkins (SOS highlighted), personnel field reports, connected node, DEGRADED nodes from fallback beacons; PLANNING mode drops named advisory markers with coverage circles, saved/loaded as local JSON |
| Live Feed | All victim messages, search + status filter, claim button, data age; encrypted rows labeled (E2E off by default, file 09 D2) |
| Nodes | /health of the connected node: GPS, both batteries, uptime, clock source, message counts, alive-peer table, DEGRADED banner |
| Personnel | Issue credentials (one-time PIN shown large, copy button, never stored), list, revoke with the DTN-latency caveat spelled out |
| Announcements | Compose with priority (HQ), list |
| Drone | LOCKED Stage 0 gate screen: no telemetry or control code exists until docs/DRONE_LINK.md is filled in on the bench (master plan D5); Stage 1 lands here in milestone M3 |
| Settings | Node URL, fleet CA loading (pinning fails closed without it), labeled insecure dev toggle, MBTiles file, MAVLink target presets (DIRECT / MESH RELAY, file 08), labeled break-glass HQ key |

## Auth

HQ operators log in with personnel_id + PIN like everyone else (file 09
plane 2); the static HQ key is a break-glass credential for a fresh fleet
whose personnel table is still empty, and the UI labels it as such.

## Development

```
cd gcc_app
flutter pub get
flutter test          # 10 widget/unit tests
flutter analyze
flutter run -d windows    # or -d macos on a Mac with full Xcode
```

Local end-to-end against a real backend: start a node from backend/
(see tools/local_two_node_test.sh for the env recipe), set the base URL
in Settings to http://127.0.0.1:18543, or enable TLS with a cert from
deploy/make_fleet_ca.sh and load fleet_ca.crt in Settings.

## Acceptance mapping (file 04)

1. Live feed / nodes / offline map with pins, internet off: implemented;
   field check happens on the rebuilt fleet.
2. Personnel round trip across drones: backend side proven by
   tools/local_two_node_test.sh; GCC UI wraps the same endpoints.
3. Announcement to rescue app: pending package 05 (rescue app update).
4. Planning marker save/restart/reload: implemented + unit tested.
5. Stage 1 telemetry: milestone M3, gated on Stage 0 (docs/DRONE_LINK.md).
