# DRONE_LINK: system drone control link (file 04 Stage 0 + file 08)

Status: architecture FINALISED 2026-07-18. DRONE_S is a full DTN mesh node
plus a MAVLink gateway. Supersedes the 2026-07-16 interim (which assumed a
single-radio Pi and the ESP32 as the link); a second AR9271 was added.

## 1. Confirmed hardware (AeroSync 5 system drone)

- Frame: 225 mm carbon racing quad, 2200 kV motors, 40 A 2-4S ESCs with a
  5 V/3 A BEC, 5 inch tri-blade props (removed for all ground testing).
- Flight controller: CC3D Open Revolution Mini, running MAVLink-capable
  firmware (a GCS talks to it and shows telemetry). No reflash performed.
- GPS module: present, wired to the CC3D (not a separate node sensor).
- Raspberry Pi 4B companion computer, now fitted with a SECOND AR9271
  (bought for this), so it has two usable radios like DRONE_A/B.
- ESP32 DroneBridge board: REMOVED. It was only the FC's WiFi-serial
  bridge; with the Pi wired directly to the FC it has no purpose. Removing
  it also saves mass on a tight racing frame.
- RC transmitter: NOT available. Operation is GCS-only (bench note in 4).

## 2. Phase goal (props off, ground only)

Turn the drone's motors on from the GCC and prove the command pipeline,
props off, secured. Motor test from the GCC is the deliverable; guided
flight is out of scope (no RC, no tuning time, bench racing quad).

## 3. Architecture: DRONE_S is a full node + gateway

The second AR9271 restores the original file-08 design fully. DRONE_S runs
the same node software as A/B and joins the mesh as a real peer:

- onboard WiFi -> RESCUE_S 5 GHz AP at 10.42.0.1 (direct GCC control and
  bonus victim coverage)
- AR9271 -> 2.4 GHz IBSS mesh at 10.99.0.3 (a real DTN peer that syncs
  messages/personnel/etc with A and B, AND carries relayed control)
- Pi <-> CC3D over a serial wire, running mavlink_gateway/mav_gateway.py

Two CONTROL paths, both live (never store-and-forward, file 08 rule):

- DIRECT: laptop joins RESCUE_S, GCC targets 10.42.0.1:14550.
- RELAY via a volunteer drone: laptop joins RESCUE_A/B, GCC targets
  10.99.0.3:14550. The volunteer Pi forwards that to the mesh (nftables
  rule already in deploy/files/nftables-volunteer.nft), reaching the
  gateway on DRONE_S. This is the "control the system drone through a
  volunteer drone's module" path, and it is LIVE MAVLink, not DTN sync.

The gateway also TAPS the FC telemetry (read-only) to give DRONE_S its own
position/battery/time without an aux module: GPS_RAW_INT -> /health GPS,
SYS_STATUS -> flight-battery voltage, SYSTEM_TIME -> sets the Pi clock from
GPS time. So the drone's own GPS makes DRONE_S a self-locating, time-synced
node. No INA3221, no LoRa, no separate GPS module needed.

## 4. Wiring the Pi to the flight controller (no reflash)

CC3D is 3.3 V logic, Pi GPIO UART is 3.3 V: direct connection, no level
shifter. FC telem TX -> Pi pin 10 (RX), FC telem RX -> Pi pin 8 (TX),
GND -> GND. Then FC_SERIAL=/dev/serial0. setup_node.sh (DRONE_CONTROL=true)
frees the primary UART from the login console, enables it, and adds the
service user to dialout. A USB-TTL adapter (FC_SERIAL=/dev/ttyUSB0) is the
alternative. Confirm the FC telemetry baud and set FC_BAUD (CC3D telem is
commonly 57600). The FC serial was already emitting MAVLink (the ESP32
used it), so nothing on the FC changes.

## 5. Arming without an RC transmitter (bench-only)

The motor test needs no arming and no RC (MAV_CMD_DO_MOTOR_TEST spins one
motor at a set throttle for a few seconds); it is the primary, safest
demo. If GCS arming is wanted, relax ARMING_CHECK and the RC/throttle
failsafe params in Mission Planner: BENCH-ONLY, NOT airworthy, revert
before any flight.

## 6. MAVLink 2 signing (file 09 plane 4) - honest status

Not implemented this phase. The GCC's Dart MAVLink library's outbound
signing support is unconfirmed, and the Python gateway forwards raw bytes
(it does not add signing). Compensating controls: the direct link is the
closed RESCUE_S AP, and the relay path is restricted by nftables on
DRONE_S (deploy/files/nftables-drone-s.nft: UDP 14550 accepted only from
10.42.0.0/24 and the volunteer mesh addresses 10.99.0.1/2). MAVLink 2
packet signing between GCC and FC is recorded as honest residual risk and
future work.

## 7. Code and deploy (this phase)

- mavlink_gateway/mav_gateway.py: transparent serial<->UDP bridge + FC
  telemetry tap. Self-contained (pyserial + pymavlink). Runs as
  rescue-mesh-mavgw.service, enabled only when DRONE_CONTROL=true.
- deploy: drone_s.conf (FC_SERIAL/FC_BAUD/MAVLINK_UDP_PORT), setup_node.sh
  installs the gateway deps + service + serial access on DRONE_S,
  nftables-drone-s.nft locks the MAVLink port.
- gcc_app: Drone tab speaks MAVLink UDP with the DIRECT/RELAY presets;
  every command gated on a <2 s heartbeat, always-on force DISARM.
- Tests: tools/mavgw_pty_test.py (gateway, 9 checks), gcc_app
  test/mav_service_test.dart (wire format + gate). No hardware needed.
