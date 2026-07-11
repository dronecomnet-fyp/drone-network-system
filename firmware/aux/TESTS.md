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
   - `{"type":"battery","bat_a_v":...,...}` with a plausible voltage on
     the channel your bench supply feeds (CH2 = Battery B pads).
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

1. Wire Battery B through INA3221 CH2 (the module self-monitors).
2. Log serial `battery` lines for 10 minutes in NORMAL
   (`python3 tools/aux_sim.py --port <port> --log normal.jsonl`).
3. Repeat for 10 minutes in FALLBACK (stop pings, keep logging from the
   second module is not possible; instead power the module from Battery B
   and log CH2 with a multimeter or repeat with the sim attached but not
   pinging).
4. Average the bat_b_ma values for each mode and compare against the
   battery capacity decision doc (177 mA class assumption).

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
