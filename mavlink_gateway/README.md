# mavlink_gateway: system drone (DRONE_S) MAVLink gateway (file 08)

Runs on the Raspberry Pi 4 mounted on the AeroSync 5 system drone. It is
the extra service that makes DRONE_S controllable, on top of the normal
node software (api, sync daemon, portal) it runs like DRONE_A/B.

## What DRONE_S is now (with the second AR9271)

A full DTN mesh node, identical software to A and B, PLUS this gateway:

- onboard WiFi -> `RESCUE_S` 5 GHz AP at 10.42.0.1 (direct GCC control +
  bonus victim coverage)
- AR9271 -> 2.4 GHz IBSS mesh at 10.99.0.3 (a real peer that syncs with
  A and B, and the live relay path for control)
- Pi <-> CC3D Revo Mini over a serial wire (this gateway)
- NO aux module: no INA3221, no LoRa, no separate GPS. The drone's GPS is
  on the flight controller, and this gateway harvests it (below).
- NO ESP32: it was the WiFi-serial bridge for the FC; with the Pi wired
  directly to the FC it has no job and is removed. No reflash of the FC
  or anything else is needed.

## What the gateway does

1. Transparent control bridge. Forwards raw MAVLink bytes both ways
   between the FC serial link and UDP `0.0.0.0:14550`. Two live paths:
   - direct: laptop on RESCUE_S -> `10.42.0.1:14550`
   - relay:  laptop on RESCUE_A/B -> volunteer Pi forwards -> mesh ->
     `10.99.0.3:14550`
   Bytes are never altered, so a command cannot be corrupted, and nothing
   is ever queued: control is live-only (file 08 rule).

2. Telemetry tap (read-only). Parses a copy of the FC stream and writes
   the drone's own sensors into the node's `/health`, since DRONE_S has no
   aux module:
   - GPS_RAW_INT -> position, 3D fix, satellites
   - SYS_STATUS  -> flight-battery voltage
   - SYSTEM_TIME -> sets the Pi clock from GPS time (once, then hourly,
     via the same narrow sudoers `date -u -s` aux_bridge uses)
   Output goes to `AUX_STATE_FILE` in the schema `api.py`'s /health reads
   (kept in step with `backend/aux_state.py`).

## Wiring the Pi to the flight controller

The CC3D Revo Mini is 3.3 V logic, and so are the Pi's GPIO UART pins, so
they connect directly with no level shifter:

| CC3D telem UART | Pi |
|-----------------|----|
| TX  | GPIO15 / pin 10 (Pi RX) |
| RX  | GPIO14 / pin 8  (Pi TX) |
| GND | any Pi GND |

Then `FC_SERIAL=/dev/serial0`. Alternatively a USB-TTL adapter gives
`/dev/ttyUSB0`; either works, it is just the `FC_SERIAL` value. Confirm
the FC telemetry baud (CC3D telem is commonly 57600) and set `FC_BAUD` to
match. The FC serial port must already be emitting MAVLink telemetry
(it was, since a GCS talked to it through the ESP32); no reflash needed.

## Config (from /etc/rescue-mesh/node.env)

| Var | Meaning | Default |
|-----|---------|---------|
| FC_SERIAL | serial device to the FC | /dev/serial0 |
| FC_BAUD | FC telemetry baud | 57600 |
| MAVLINK_UDP_PORT | UDP port the GCC connects to | 14550 |
| AUX_STATE_FILE | health state file | /run/rescue-mesh/aux_state.json |
| DATE_SET_CMD | sudoers-backed clock set | sudo -n /bin/date -u -s {utc} |

## Why a small Python bridge, not mavlink-router

File 08 allowed either. mavlink-router is not in Bookworm apt and needs a
source build; MAVProxy is heavier and GCS-oriented. A ~200-line bridge
using pyserial + pymavlink is self-contained, versioned in this repo,
deploys with the rest of the node, and is unit-tested end to end
(`tools/mavgw_pty_test.py`, no hardware). Routing needs here are simple
(one FC serial, a few UDP clients), so the bridge is the right size. If a
future need appears (many GCS, MAVLink 2 signing offload), mavlink-router
is the documented upgrade.

## Test

`backend/.venv/bin/python tools/mavgw_pty_test.py` runs a fake FC on a pty
and a fake GCS on UDP, and checks both-way byte-exact forwarding plus the
GPS/battery/clock tap. Nine checks, no hardware.
