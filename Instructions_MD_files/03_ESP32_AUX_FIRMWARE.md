# 03 ESP32-C3 AUXILIARY MODULE: UNIFIED FIRMWARE

Goal: one Arduino (ESP32 core) firmware for the Seeed XIAO ESP32-C3 that
merges the three working test sketches (com_module_lora, com_module_gps,
com_module_ina3221) and implements design v3 sections 3.1 to 3.4: sensor
feeder in normal mode, independent LoRa beacon in fallback mode, BLE
advertising, last-message flash cache, and the JSON serial protocol.

## Pin map (single source of truth)

Use the CORRECTED pin set from com_module_gps.txt (the earlier
com_module_lora.txt used a different, superseded mapping; do not mix them):

| Function            | XIAO pin | Notes                          |
| LoRa CS             | D3       | RFM95 NSS                      |
| LoRa DIO0           | D1       |                                |
| LoRa RST            | D2       |                                |
| LoRa SCK            | D8       | customSPI(FSPI)                |
| LoRa MISO           | D9       | corrected value                |
| LoRa MOSI           | D10      |                                |
| GPS RX (module TX)  | D7 (GPIO20) | Serial1, 9600 baud          |
| GPS TX (module RX)  | D6 (GPIO21) |                             |
| I2C SDA (INA3221)   | D4 (GPIO6)  | address 0x40, A0 to GND     |
| I2C SCL (INA3221)   | D5 (GPIO7)  |                             |
| Pi link             | USB-C (native USB CDC), 115200 | no GPIO used |
| Free                | D0       | reserve for future use         |

INA3221 shunts are 100 milliohm (from the working test sketch). Channel
mapping per design v3: CH1 = Battery A (Pi side), CH2 = Battery B (aux),
CH3 = spare.

Power note: Battery B (1S 2400 mAh) connects to the XIAO battery pads; the
Pi's USB connection also supplies VBUS in normal operation. Design v3 states
Battery B stays charged from the Pi USB and takes over in fallback. Before
trusting this in a long test, VERIFY on the Seeed XIAO ESP32-C3 wiki that
simultaneous USB + battery is a supported configuration of its charging
circuit, and measure charge current once hardware is on the bench.
Confidence pending that check: Moderate.

## Libraries

SPI, LoRa (sandeepmistry, already proven in the tests), TinyGPSPlus,
INA3221 lib already used in the test sketch, Preferences (flash cache),
ArduinoJson (serial protocol), NimBLE-Arduino (advertising). Pin exact
library versions in a platformio.ini or a documented Arduino IDE setup so the
build is reproducible for the report.

## Firmware structure

State machine: INIT -> NORMAL -> FALLBACK (one-way per boot; a fresh ping
after fallback may transition back to NORMAL only if the team decides so;
default per design v3 is to stay in fallback until power cycle, simpler to
reason about; document the choice in code comments).

INIT:
- Start USB serial, Serial1 GPS, I2C, SPI, LoRa.begin(915E6) with
  setTxPower(LOW during bench work, per master plan R1), SF7, BW125k.
- Load last_msg from Preferences (defaults: msg_id="none",
  content="no messages yet") per design v3 layer 8.
- Start BLE advertising (below).
- Record millis() as last_ping = now so a Pi that boots slowly is not
  instantly declared dead; require the FIRST ping within 60 s, then apply
  the 15 s rule.

NORMAL loop (all non-blocking, single loop() with millis() timers):
- Continuously feed GPS bytes to TinyGPSPlus.
- Every 5 s: send {"type":"gps",...} and {"type":"battery",...} to the Pi
  (fields exactly per the design v3 serial table).
- On first valid GPS date+time and every re-fix: send {"type":"gps_time",
  "utc":"YYYY-MM-DDTHH:MM:SSZ","fix":1,"sats":N}.
- Parse inbound lines with ArduinoJson:
  - ping -> last_ping = millis()
  - last_msg -> truncate content to 100 chars, Preferences write, reply
    {"type":"last_msg_ack","msg_id":...}
  - lora_tx -> transmit payload over LoRa
  - ble_update -> update advertisement payload
- LoRa receive: on packet, if payload starts with "FB|" forward to Pi as
  {"type":"fallback_rx", raw:..., rssi, snr}; else forward as
  {"type":"lora_rx", payload, rssi, snr}.
- Fallback trigger: millis() - last_ping > 15000 -> FALLBACK.

FALLBACK loop:
- Stop BLE advertising (design v3: conserve Battery B).
- Every 30 s build and send the beacon EXACTLY in the design v3 format:
  FB|<node_id>|<lat>|<lon>|<gps_fix>|<utc>|<bat_a_v>|<bat_a_mA>|<bat_b_v>|
  <bat_b_mA>|<msg_id>|<msg_content_100>|<msg_time>|DOWN
  (pipe character as separator; keep total <= 255 bytes; sanitize pipes out
  of message content when caching it).
- Keep listening for LoRa packets and keep parsing GPS between transmits.

node_id: stored in Preferences, set once per board via a serial command
{"type":"set_node_id","node_id":"DRONE_A"} so one firmware binary serves all
three modules (mirrors the SSID-configurability fix on the Pi side).

## BLE advertising (this replaces the failed Pi approach)

- NimBLE advertisement, connectable=false, containing Service Data for a
  project-fixed 128-bit UUID (generate once, hardcode fleet-wide, document
  in design v4). Service data payload, compact: `nodeId|ssid`
  (e.g. `A|RESCUE_A`). Advertising interval around 500 ms to 1 s.
- Local name: "RESCUE-A" for humans using generic scanner apps.
- The emergency app (file 06) filters scans by this service UUID. Keep the
  payload under the legacy 31-byte advertisement budget; if it does not fit,
  move the SSID to scan-response data.
- Optional stretch, NOT required for MVP: alternate an iBeacon-format frame
  for faster iOS region wake. Implement only after file 06 MVP works.

## Bench test procedure (write as firmware/TESTS.md, beginner level, exact steps)

1. Component regression: with the unified firmware flashed, verify GPS lines
   print, INA3221 rows print with a bench supply on CH2, LoRa packet reaches
   the second module's receiver sketch (reuse the existing receiver code).
2. Serial protocol: connect XIAO to a laptop, run a provided
   tools/aux_sim.py (write it: sends pings, prints JSON, lets you inject
   last_msg and lora_tx) and tick through every message type in the design
   v3 table.
3. Fallback drill: stop the ping sender, confirm beacon appears on the second
   module within 15 to 45 s, confirm the second module (connected to a Pi
   running file 02's aux_bridge) produces a node_health degraded row.
4. Flash cache: send last_msg, power-cycle the XIAO, trigger fallback,
   confirm the beacon carries the cached message.
5. BLE: nRF Connect on a phone shows the service UUID and payload; confirm
   advertising STOPS in fallback.
6. Duty-cycle sanity: with INA3221 CH2 self-monitoring Battery B, log average
   current for 10 minutes in NORMAL and in FALLBACK and compare against the
   battery decision doc figures (177 mA class). If measured normal-mode
   current exceeds the doc's assumption materially, flag it: the 10 h
   Battery B claim in the battery decision doc would need revisiting
   (rule 9: changed figures must be called out, not silently absorbed).

## Acceptance for file 03

All six bench tests pass, one binary + per-board node_id provisioning works
on both aux modules (only two exist; DRONE_A and DRONE_B carry them, DRONE_S
flies without one per file 08), and TESTS.md is reproducible by a teammate
who has never opened the code.
