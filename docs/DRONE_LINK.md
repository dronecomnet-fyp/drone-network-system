# DRONE_LINK: system drone control link (file 04 Stage 0 + file 08)

Status: Stage 0 CONFIRMED by the team (2026-07-16). The AeroSync 5 system
drone speaks MAVLink already, so no reflash was needed for this phase.

## 1. Confirmed hardware (from the team, AeroSync 5 unit)

- Frame: 225 mm carbon racing quad, 2200 kV motors, 40 A 2-4S ESCs with a
  5 V/3 A BEC, 5 inch tri-blade props (removed for all ground testing).
- Flight controller: CC3D Open Revolution Mini. It answers MAVLink to a
  ground station (confirmed: a GCS connects and shows telemetry), so it is
  running ArduPilot/MAVLink-compatible firmware. No reflash performed.
- Telemetry gateway: ESP32 dev board running DroneBridge, wired to the
  CC3D over serial. It exposes a 2.4 GHz Wi-Fi AP and bridges Wi-Fi UDP
  MAVLink to the FC serial. This IS our MAVLink transport; the GCC talks
  UDP to it (default 192.168.2.1:14550).
- Onboard GPS module present (rear/bottom platform).
- RC transmitter: NOT available to the team. Operation is GCS-only. See
  the arming note below; this is a documented bench-only configuration.
- Spare Raspberry Pi 4B available, but with NO AR9271 and NO aux module.

## 2. Phase goal (descoped, honest)

Turn the drone's motors on from the GCC and prove the command pipeline,
PROPS OFF, on the ground. No flying, no tuning (no time, and a bench
racing quad needs failsafe/tuning work before any autonomous flight).
Concretely: GCC connects over DroneBridge, shows live telemetry, and a
motor test spins a motor at low throttle from a GCC button. Guided
"go to marker" is a stretch that needs an outdoor GPS fix and is not
required this phase.

## 3. Control paths, and why the relay is not available this phase

Two paths were considered (master plan D7 / file 08):

- DIRECT (implemented, the demo): laptop joins the ESP32 DroneBridge AP;
  the GCC Drone tab speaks MAVLink UDP straight to the FC. Reliable, zero
  extra hardware. This is what spins the motors.

- RELAY via a volunteer drone (NOT available this phase, with reasoning):
  the original file-08 design mounted a third Pi as a full mesh node
  (DRONE_S at 10.99.0.3) running a MAVLink gateway, so the GCC could reach
  the drone across the 2.4 GHz DTN backbone. That required the system
  drone's Pi to carry an AR9271 on the IBSS cell. The actual system-drone
  Pi has a SINGLE onboard radio and no AR9271. A single radio cannot be on
  the mesh/user side and talk to the 2.4 GHz ESP32 at the same time, so
  the system drone cannot be a DTN node this phase. Re-banding a volunteer
  AP to 2.4 GHz so the ESP32 could join it was already rejected (master
  plan R2 interference), and time-slicing one radio is disqualified for a
  LIVE control link by file 08's own rule ("flight commands only over a
  live link, never store-and-forward") and by the >=2 s heartbeat gate.
  Conclusion: DIRECT control this phase; the mesh-relayed control path is
  future work needing a second radio on the system drone. Stated plainly
  to examiners as a resource limitation, not hidden.

Note: this limitation does NOT touch the rest of the system. The DTN mesh
(DRONE_A <-> DRONE_B on the AR9271 IBSS) and the 5 GHz user APs are
independent of the drone control link; victims still join and A/B still
sync regardless of how the drone is controlled.

## 4. Arming without an RC transmitter (bench-only)

ArduCopter normally wants RC present. For props-off ground testing with
no transmitter, the runbook sets these parameters and labels them
BENCH-ONLY, NOT airworthy:

- Motor test needs no arming and no RC: MAV_CMD_DO_MOTOR_TEST spins a
  single motor at a set throttle percent for a few seconds. This is the
  primary demo and the safest.
- If arming from the GCS is wanted, relax the RC and arming checks
  (e.g. ARMING_CHECK bits, and a throttle-failsafe/RC-source param set)
  per the runbook. These MUST be reverted before any real flight.

## 5. MAVLink 2 signing (file 09 plane 4) - honest status

The GCC uses the Dart `dart_mavlink` package. It parses MAVLink v2 frames
(including the signed-flag) and serialises v2, but its outbound message
SIGNING support is not confirmed. Rather than claim signing we do not
have, this phase relies on file 09 plane 4 LAYER 1 (network isolation):
the DroneBridge control AP is a closed point-to-point link between the
one GCC laptop and the drone, not exposed to the user/mesh planes. That
is the compensating control, and MAVLink 2 packet signing between GCC and
FC is recorded here as the honest residual risk and future work. On the
mesh-relayed path (also future work) the nftables port lockdown in
deploy/files/nftables-drone-s.nft would additionally apply.

## 6. What the GCC implements (this phase)

backend/none; all in gcc_app:
- lib/mavlink/mav_service.dart: UDP transport, ardupilotmega parse,
  telemetry decode (heartbeat/armed/mode, SysStatus battery, GpsRawInt,
  GlobalPositionInt, Attitude, Statustext, CommandAck), and commands
  (arm/disarm, force-disarm kill, DO_MOTOR_TEST, DO_SET_MODE, RTL/LAND).
- Every command control is gated on a heartbeat fresher than 2 s
  (DroneController.linkFresh); force-DISARM is always available.
- Tests in test/mav_service_test.dart prove the wire format and the gate.
