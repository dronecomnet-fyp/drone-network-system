# Aux module bench tests (file 03)

Beginner-level, exact steps. Log every run in docs/test_log.md. Acceptance
for file 03: all six tests pass, one binary + per-board node_id
provisioning works on BOTH aux modules (DRONE_A and DRONE_B carry them;
DRONE_S flies without one per file 08), and a teammate who has never
opened the code can reproduce this file.

## Setup you need once

- PC with PlatformIO (`pip install platformio`) or the Arduino IDE
  (see README.md for the IDE library versions).
- Flash: connect the XIAO by USB-C, then `pio run -t upload` from
  `firmware/aux/`.
- Provision the board identity (once per board, survives reflashes):
  open a serial terminal at 115200 (`pio device monitor` or
  `python3 tools/aux_sim.py --port /dev/ttyACM0` from the repo root) and
  send: `{"type":"set_node_id","node_id":"DRONE_A"}`
  Expect: `{"type":"set_node_id_ack","node_id":"DRONE_A"}`

## Test 1: component regression

With the unified firmware flashed and the module on a bench supply:

1. Take the module OUTDOORS or near a window (GPS needs sky).
2. Watch the serial stream. Within a few minutes expect, every 5 s:
   - `{"type":"gps","fix":1,"lat":...,"lon":...,"sats":N,...}` (fix flips
     from 0 to 1 when the antenna sees satellites)
   - `{"type":"battery","bat_a_v":...,"bat_a_ma":...,"bat_b_v":...,
     "bat_b_ma":...}`: Battery A is INA3221 CH1, Battery B is CH2.
   - CHECK THE SIGN, per channel, because both channels are bidirectional.
     With the pack running a load, the current must be POSITIVE. Then put
     that pack on charge: the same field must go NEGATIVE while voltage
     rises. If a channel reads negative under load (and positive on
     charge), its shunt is wired the other way round: set
     `BATT_A_SHUNT_INVERT` / `BATT_B_SHUNT_INVERT` to `true` in
     `src/main.cpp` and reflash, rather than re-soldering.
   - A resting pack sits within a few tenths of a mA of zero, either side.
     That is the 0.4 mA/count resolution, not a real direction; the apps
     call anything under `kBatteryIdleMa` (5 mA) idle.
   - A channel the chip cannot answer for reports `null`, which is not the
     same as `0` (no reading vs no current).
   - A channel with NO BATTERY on it must also report `null`. An
     unconnected INA3221 input floats up near the supply rail and field
     testing saw Battery B report a confident 4.18 V with nothing attached,
     which is indistinguishable from a full pack. Set `BATT_A_PRESENT` /
     `BATT_B_PRESENT` false for a channel that is not wired. Better, tie
     that channel's IN+ and IN- to GND: it then reads about 0 V and the
     `BATT_MIN_PLAUSIBLE_V` floor catches it with no flag to remember.
3. LoRa path: flash the SECOND module with the same firmware (it doubles
   as the receiver). On module 1's serial, send
   `{"type":"lora_tx","payload":"hello-bench"}`.
   On module 2's serial expect `{"type":"lora_rx","payload":"hello-bench",
   "rssi":...,"snr":...}`.

Pass: all three subsystems report on one firmware build.

## Test 2: serial protocol walkthrough

1. Connect the XIAO to a laptop, run
   `python3 tools/aux_sim.py --port <port>`.
2. The sim pings every 5 s and pretty-prints everything the module says.
3. Tick through every message type from the design v3 table:
   - inbound to Pi: `boot`, `gps`, `battery`, `gps_time` (needs fix),
     `lora_rx`, `fallback_rx` (needs test 3), `last_msg_ack`
   - outbound from Pi (type them in the sim): `ping` (automatic),
     `last_msg`, `lora_tx`, `ble_update`, `set_node_id`
4. Send `last_msg` with a content over 100 chars and one containing `|`;
   confirm the ack and that the cache sanitizes both (visible in test 4's
   beacon).

Pass: every message type observed with correct fields.

## Test 3: fallback drill

1. Module 1 running with aux_sim pinging; module 2 connected to a Pi
   running backend v2 (rescue-mesh-auxbridge active).
2. Stop the sim (Ctrl-C stops the pings) but keep the module powered
   (that is the point of Battery B).
3. Expect on module 1 within 15-45 s: `{"type":"fallback_enter"}` then a
   LoRa `FB|...` beacon every 30 s.
4. On the Pi behind module 2: `sqlite3 drone_mesh.db "SELECT node_id,
   degraded, ts FROM node_health ORDER BY ts DESC LIMIT 3;"` shows a
   degraded=1 row for module 1's node_id, and audit.log contains
   FALLBACK_BEACON.

Pass: beacon within 45 s, degraded row appears.

## Test 3b: fallback RECOVERY drill (the one that matters in the field)

Entering fallback is easy to trigger by accident: 15 s of Pi silence is
enough, and an ordinary `systemctl restart rescue-mesh-auxbridge` can take
that long. Before CHANGES.md item 31 the module then beaconed forever and
stayed BLE-dark until someone power-cycled it, so a healthy drone looked
DOWN to the whole fleet. This test proves it now heals itself.

1. From the end of test 3, with module 1 in FALLBACK and beaconing.
2. Restart the pings (`aux_sim.py` again, or restart the aux bridge on the
   Pi). Do NOT power-cycle the module.
3. Expect within about 15 s (3 pings at 5 s):
   `{"type":"fallback_exit"}` on serial, then `gps` and `battery` lines
   resuming every 5 s, and the `FB|` beacons STOPPING.
4. Rescan with nRF Connect: BLE advertising is back (it stops in fallback).
5. On a neighbouring node, `curl -sk https://10.42.0.1:8443/health` must no
   longer list module 1's node under `degraded_nodes`, within
   FALLBACK_EXPIRY (120 s) at the latest, and sooner if that node is an
   alive DTN peer.

Pass: exits fallback within ~20 s of pings resuming, beacons stop, BLE
returns, and the neighbour stops reporting it degraded without anyone
touching the database.

Also confirm it does NOT flap: send a single ping, then go quiet again for
30 s. The module must STAY in fallback (recovery needs 3 consecutive
pings), which is what stops a half-dead Pi toggling the fleet's view.

## Test 4: flash cache across power cycle

1. With the sim, send
   `{"type":"last_msg","msg_id":"m-1","content":"cache test","timestamp":"2026-07-11T12:00:00Z"}`.
2. Unplug the module completely, plug it back in.
3. Trigger fallback (no pings for 60 s after boot).
4. Capture the beacon on the second module: it must carry `m-1|cache test`.

Pass: cached message survives the power cycle (design v3 layer 8).

## Test 5: BLE advertising

1. Phone with nRF Connect (or equivalent BLE scanner).
2. In NORMAL mode: scan shows local name `RESCUE-A` (scan response) and
   service data under UUID 2b57461c-1c04-49c4-944a-13643c1618da with
   payload `A|RESCUE_A`.
3. Advertising interval: nRF Connect's interval readout should sit in the
   0.5-1 s range.
4. Trigger fallback (test 3) and rescan: the advertisement must be GONE
   (BLE stops in fallback to conserve Battery B).

Pass: UUID + payload visible in NORMAL, absent in FALLBACK.

## Test 6: duty-cycle sanity (rule 5 figure check)

Battery B is on INA3221 CH2, so `bat_b_ma` measures this directly.

1. Run the module from Battery B with nothing charging it, so the reading
   is pure draw. Confirm `bat_b_ma` is POSITIVE before you start: a
   negative figure means the pack is on charge (or the shunt is reversed,
   see test 1) and the averages below would be meaningless.
2. Log serial `battery` lines for 10 minutes in NORMAL
   (`python3 tools/aux_sim.py --port <port> --log normal.jsonl`).
3. Repeat for 10 minutes in FALLBACK (stop pings so the module enters
   fallback; keep it powered).
4. Average `bat_b_ma` per mode and compare against the battery capacity
   decision doc (177 mA class assumption). `bat_b_v` tracks the pack sag
   over the run as a cross-check.

Note the measurement ceiling: with the 0.100 ohm shunt the channel
saturates at about +/-1638 mA and CLIPS rather than wrapping, so a draw or
charge current beyond that is under-reported, not wrong-signed.

Pass: measured averages recorded in docs/test_log.md. If NORMAL-mode
current exceeds the doc's assumption materially, FLAG IT in
docs/CHANGES.md: the 10 h Battery B runtime claim would need revisiting.

## Power configuration note (verify before any long unattended test)

Battery B (1S 2400 mAh) on the XIAO battery pads while USB supplies VBUS:
design v3 states Battery B charges from the Pi USB and takes over in
fallback. VERIFY on the Seeed XIAO ESP32-C3 wiki that simultaneous USB +
battery is a supported configuration of its charging circuit, and measure
the charge current once on the bench. Confidence pending that check:
Moderate (file 03 power note).

With Battery B on INA3221 CH2 the charge current is now directly readable,
so that open item is answered from `bat_b_ma` rather than an external
meter. This also gives the expected SIGN per mode, which is the quickest
health check on the whole power design:

| Mode                       | Expected `bat_b_ma`                       |
| -------------------------- | ----------------------------------------- |
| NORMAL, Pi USB present     | NEGATIVE (charging), tapering toward 0    |
| NORMAL, pack already full  | around 0 (idle / float)                   |
| FALLBACK, Pi dead, no VBUS | POSITIVE (the pack is now running things) |

A pack reading positive while the Pi is alive and USB is present means it
is NOT being charged: either the charging path is not working (the thing
file 03 asks to verify) or that channel's shunt is reversed (test 1).
Record the measured charge current in docs/test_log.md; if the pack does
not actually charge from Pi USB, that breaks design v3's "takes over in
fallback" story and must be flagged in docs/CHANGES.md under rule 5.
