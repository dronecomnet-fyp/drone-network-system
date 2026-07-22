# 11 The System Drone and Flight Control

Most drones in the fleet only carry a communication module; their flight is
their own pilots' job. One drone is different: the **system drone**, DRONE_S
(an AeroSync 5), also carries a flight controller the GCC can command over
MAVLink. This chapter covers that drone, the software that reaches its flight
controller, the fleet manager that coordinates deployments, and the safety
policy that governs all of it. It draws on
`Instructions_MD_files/08_SYSTEM_DRONE_RELAY_NODE.md` ("file 08") and
`docs/DRONE_LINK.md`.

## The safety policy (read this first)

**In this phase the drones are not flown.** The system drone's flight commands
are verified on the bench with all four propellers removed. This is a
deliberate safety choice, not a missing capability: the command pipeline is
real, it acks, and it spins motors on a bench motor test; actual free flight
waits until a proper safety setup is done (there is no RC transmitter, and the
flight controller is untuned). Every place in the code and UI that touches
flight says so, and force-DISARM is always reachable. The next team must keep
this policy until they deliberately, and with a safety plan, change it.

## The hardware

- Frame: a 225 mm carbon racing quad, 2200 kV motors, 40 A 2-4S ESCs, 5 inch
  props (removed for all ground testing).
- Flight controller: a **CC3D Open Revolution Mini**, already running
  MAVLink-capable firmware (a ground station talks to it and shows telemetry).
  No reflash was performed.
- A GPS module wired to the flight controller.
- A Raspberry Pi 4B companion computer, fitted with a **second AR9271** so it
  has two usable radios like the other nodes.

## Why DRONE_S needed a second radio

This is the key architecture story for this node. Recall from chapter 04 that
the mesh must be an AR9271 (the Pi's onboard radio cannot do IBSS) and the user
AP must be the onboard radio. For a while the plan was that DRONE_S, with a
single AR9271, could not be a mesh node and would talk to its flight controller
over a separate ESP32 Wi-Fi bridge, controllable only directly.

The team then bought a **second AR9271** for DRONE_S. That changed everything
(recorded in `docs/CHANGES.md` items 16-19):

- DRONE_S now has two radios like A and B: onboard Wi-Fi is the `RESCUE_S` user
  AP at `10.42.0.1`, and one AR9271 is the 2.4 GHz IBSS mesh peer at
  `10.99.0.3`. It is a **full mesh node** running the same software as A and B.
- The **ESP32 was removed**. It was only the flight controller's Wi-Fi-to-serial
  bridge; with the Pi wired directly to the flight controller it has no purpose,
  and removing it saves mass on a tight frame.
- The Pi connects to the CC3D **directly over serial**. The recommended path is
  the flight controller's micro-USB port, which on ArduPilot is SERIAL0 speaking
  MAVLink by default; it appears on the Pi as `/dev/ttyACM0` with no flight
  controller configuration and no wiring. The GPIO UART (`/dev/serial0`, 3.3 V,
  no level shifter) is the alternative.

So DRONE_S serves victims and rescuers on `RESCUE_S` exactly like A and B, syncs
over the mesh, and is a MAVLink gateway, all at once.

## The MAVLink gateway

`mavlink_gateway/mav_gateway.py` runs on DRONE_S's Pi. It is a self-contained
transparent bridge: it forwards raw MAVLink bytes between the flight
controller's serial port and a UDP socket on `0.0.0.0:14550`, never altering a
packet, live only (no store-and-forward, a hard file 08 rule for control
traffic). It also taps the telemetry read-only to give DRONE_S its own
position, battery, and time without an aux module: `GPS_RAW_INT` becomes the
node's GPS, `SYS_STATUS` the flight-battery voltage, and `SYSTEM_TIME` sets the
Pi clock from GPS time. So the drone's own GPS makes DRONE_S a self-locating,
time-synced node with no INA3221, no LoRa, and no separate GPS module.

It runs as `rescue-mesh-mavgw.service`, enabled only on the node whose config
sets `DRONE_CONTROL=true` (chapter 14).

## Two control paths, both live

The GCC reaches the flight controller two ways, and both are live MAVLink, never
DTN sync:

- **Direct**: the laptop joins `RESCUE_S` and targets `10.42.0.1:14550`.
- **Relayed through a volunteer drone**: the laptop joins a volunteer's
  `RESCUE_A/B`, targets `10.99.0.3:14550`, and the volunteer node forwards that
  across the mesh to DRONE_S's gateway (an nftables rule permits it). This is the
  "control the system drone through a volunteer drone's module" path.

The MAVLink control port is firewalled (`deploy/files/nftables-drone-s.nft`) to
accept UDP 14550 only from the local user subnet and the volunteer mesh
addresses (file 09 plane 4 layer 1). MAVLink 2 packet signing (layer 2) is
recorded as honest residual risk and future work.

## The GCC MAVLink service

`gcc_app/lib/mavlink/mav_service.dart` is the GCC side. It speaks MAVLink 2 over
UDP with the `dart_mavlink` library (ardupilotmega dialect):

- It sends a GCS heartbeat every second and decodes telemetry (heartbeat,
  SYS_STATUS, GPS_RAW_INT, GLOBAL_POSITION_INT, ATTITUDE, STATUSTEXT,
  COMMAND_ACK).
- **The safety gate:** `linkFresh` is true only while a heartbeat has arrived in
  the last 2 seconds. The UI enables every command only when `linkFresh` is
  true. A dead link disables commands automatically.
- Commands: arm and disarm (COMPONENT_ARM_DISARM, command 400), a force-disarm
  kill that carries the 21196 magic in param2 and always works, a per-motor
  bench test (DO_MOTOR_TEST, command 209) that is the headline props-off demo,
  set mode, takeoff (NAV_TAKEOFF, 22), reposition (DO_REPOSITION, 192, sent as a
  COMMAND_INT so the lat/lon keep integer precision), and return to launch
  (NAV_RETURN_TO_LAUNCH, 20).

`DroneController` (`gcc_app/lib/state/drone_controller.dart`) is the provider
bridge, and the Drone tab (`screens/drone_control_screen.dart`) is the UI, with
the always-visible force-DISARM.

## The fleet manager

"Manage ten drones and bring them home before the battery dies" is a fleet
coordination problem, not multi-drone flight (only DRONE_S has a flight
controller we command). `gcc_app/lib/state/fleet_state.dart` handles it in two
modes behind one UI (the fleet board on Live Ops, `screens/fleet_board.dart`).

Each deployed drone runs a lifecycle state machine:

```
PLANNED -> LAUNCH_REQUESTED -> ENROUTE -> ON_STATION -> RETURNING -> LANDED
   plus  FALLBACK (only the aux LoRa beacon still heard)  and  LOST
```

- **DEMO mode** (any number of drones, exam-safe): a deterministic simulator
  advances each drone along its path, drains a modelled battery from the product
  spec, and **auto-triggers RETURNING when the remaining battery falls to a
  reserve equal to 1.5 times the energy needed to fly home**. That reserve rule
  is the answer to "bring them back before the battery dies". The battery and
  cruise figures are tunable estimates with recorded confidence (Low to
  Moderate). Volunteer rows are labelled "pilot advisory": the GCC shows the
  pilot an instruction because in reality it cannot command their flight.
- **REAL mode** (DRONE_S only): deploying runs the actual heartbeat-gated MAVLink
  sequence (set GUIDED, arm, takeoff, reposition to the placement), and a battery
  watchdog on the decoded SYS_STATUS voltage issues return-to-launch below a
  per-cell threshold (default 3.5 V per cell, standard LiPo practice, confidence
  Moderate). Props off, on the bench, per the safety policy above.

The board also does **inventory accounting**: it shows "Deployed X / Y
available" from the mission's drone inventory, and when the pool is empty the
Deploy button disables with "No more drones available". So the platform manages
the whole operation even though only one drone is really ours; the rest are
DEMO, which is the honest way to show the coordination logic. The LoRa fallback
(chapter 07) is what lets a quiet drone show as FALLBACK rather than LOST.

The state machine, the reserve-battery math, the recall, and the MAVLink wire
encodings are all unit-tested with no hardware
(`gcc_app/test/fleet_state_test.dart`, `mav_service_test.dart`).

## Where the code lives

- Gateway: `mavlink_gateway/mav_gateway.py`, `mavlink_gateway/README.md`
- GCC MAVLink: `gcc_app/lib/mavlink/mav_service.dart`,
  `gcc_app/lib/state/drone_controller.dart`
- Fleet manager: `gcc_app/lib/state/fleet_state.dart`,
  `gcc_app/lib/screens/fleet_board.dart`
- Drone tab: `gcc_app/lib/screens/drone_control_screen.dart`
- Firewall: `deploy/files/nftables-drone-s.nft`
- Config: `deploy/nodes/drone_s.conf`, `docs/DRONE_LINK.md`
- Bring-up runbooks: `deploy/windows_drone_s_bringup.html`,
  `gcc_app/windows_drone_control.html`
