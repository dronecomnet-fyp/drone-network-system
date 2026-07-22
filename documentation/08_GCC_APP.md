# 08 The Ground Control Center App

The GCC is the operator's window on the whole operation: a Flutter desktop
application delivered as an installable Windows build for the ground laptop
(the macOS target exists for development). It is specified by
`Instructions_MD_files/04_GCC_WINDOWS_APP.md` ("file 04") and lives in
`gcc_app/`. This chapter covers the app's shape and its plain-operations tabs;
mission planning, the fleet manager, and the AI advisor are big enough to have
their own chapters (11, 12).

## The connectivity model (why every screen shows an age)

The GCC laptop joins whichever `RESCUE_x` Wi-Fi is in range and talks to that
**one** node at `https://10.42.0.1:8443`. It does not see the mesh directly. Its
knowledge of the other nodes is only as fresh as that node's last sync plus
fallback beacons. So the app never pretends data is live: every dataset carries
a last-updated age, shown with a helper `formatAge()`. This honesty is a
deliberate design stance, repeated throughout the UI.

## State management

The app uses `provider` (ChangeNotifier). The core objects, all in
`gcc_app/lib/state/`:

- `AppState` (`app_state.dart`): settings (node URL, fleet CA, offline map path,
  MAVLink target, product-site and AI config), the session/login lifecycle, and
  the API client. All settings persist through `shared_preferences`.
- `DataStore` (`data_store.dart`): polls the connected node every 5 seconds and
  exposes each dataset (messages, gs messages, announcements, personnel,
  checkins, personnel locations) plus node health, each with its own
  `lastUpdated` timestamp. `isConnected` is true only if health updated within
  the last 15 seconds. This one object feeds most screens.
- `MissionState` (`mission_state.dart`): the mission and its deployments
  (chapter 12).
- `FleetState` (`fleet_state.dart`): the fleet manager (chapter 11).
- `DroneController` (`drone_controller.dart`): the MAVLink bridge (chapter 11).

All API traffic goes through the shared `RescueMeshClient` from `shared_dart`,
which does the fleet-CA pinning (chapter 05). The GCC logs in with a
personnel_id and PIN exactly like everyone else (HQ is a personnel role), with
the break-glass key as a labelled fallback.

## The tabs

The shell (`gcc_app/lib/main.dart`) is a navigation rail with these screens:

### Map (`screens/map_screen.dart`)

The home screen and the operational picture. Tiles come from a pre-downloaded
**offline MBTiles** file (there is no internet at a deployment; you prepare the
region file before the mission, `docs/OFFLINE_MAPS.md`). Layers: victim
messages (red NEW, green CLAIMED), emergency-app check-ins (blue, orange for
SOS), rescuer last-known positions (teal person pins, chapter 12), personnel
field reports (purple flags), the connected node and any degraded nodes at
their beaconed positions, the active deployment's placements with coverage
circles, and deployed drones moving through their lifecycle. It is also the
planning surface (chapter 12): draw the operation area polygon, drop and move
role-colored placements.

### Live Ops (`screens/live_ops_screen.dart`)

The numbers dashboard, added in the mission layer (chapter 12). Stat tiles for
victims, SOS, field reports, rescuers tracked, mesh/battery/GPS, each with its
data age; the fleet board (chapter 11); a rescuers card; and a known-nodes
table. Where the Map is the picture, Live Ops is the summary.

### Mission (`screens/mission_screen.dart`)

Mission setup: identity, disaster type, challenges, the resource inventory
(drones and modules), and the deployment list with the AI-suggest button. Fully
covered in chapter 12.

### Live Feed (`screens/live_feed_screen.dart`)

The raw victim message and check-in feed, newest first, with claim state and
timestamps.

### Nodes (`screens/nodes_screen.dart`)

Node health from `/health`: the connected node's GPS, battery, uptime, clock
source and message counts; its alive DTN peers; and any DEGRADED nodes learned
from LoRa fallback beacons. Every block shows its age.

### Personnel (`screens/personnel_screen.dart`)

HQ-only. Issue a rescuer a one-time PIN (shown once), list personnel (without
hash material), and revoke. This is the personnel lifecycle from the operator
side (chapter 05).

### Announcements (`screens/announcements_screen.dart`)

Read and (for HQ) post operational notices that sync to all nodes.

### Drone (`screens/drone_control_screen.dart`)

Live MAVLink telemetry and the command palette for the system drone. Every
command is gated on a fresh heartbeat, and force-DISARM is always visible.
Covered in chapter 11.

### Settings (`screens/settings_screen.dart`)

Node base URL; the fleet CA (loaded from `fleet_ca.crt`, without which HTTPS
fails closed by design); the offline map file; the MAVLink target presets
(direct and relayed); the product-site Supabase URL and anon key; the AI
advisor endpoint, model, and key; and the labelled break-glass HQ key.

## Services

`gcc_app/lib/services/`:

- `geo.dart`: pure geometry (haversine distance, point-in-polygon) used by the
  planner, the fleet manager, and the AI validator. No dependencies, trivially
  unit-tested.
- `product_api.dart`: fetches a unit's specs from the product site (chapter 13).
- `ai_advisor.dart`: the AI deployment planner (chapter 12).

`gcc_app/lib/mavlink/mav_service.dart`: the MAVLink UDP link (chapter 11).

## Building and running

- Development is on macOS (or the Windows desktop target). `flutter run -d
  macos` or `-d windows`.
- The installable Windows build steps are in `docs/RELEASES.md`; the bring-up
  runbook is `gcc_app/windows_gcc_bringup.html`.
- Tests: `flutter test` (41 tests: mission serialization, the fleet state
  machine and battery math, the MAVLink wire encodings, the AI validator, and a
  shell smoke test that every tab renders its honest empty/gated state).
  `flutter analyze` is clean.

## Where the code lives

```
gcc_app/lib/
  main.dart                 the shell + navigation + login dialog
  state/                    AppState, DataStore, MissionState, FleetState, DroneController
  screens/                  one file per tab
  services/                 geo, product_api, ai_advisor
  mavlink/mav_service.dart  the MAVLink UDP link
```
