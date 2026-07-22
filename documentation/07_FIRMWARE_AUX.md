# 07 The Aux Module Firmware

Each drone carries a small microcontroller, the "aux module", that does the
jobs the Pi cannot do well or cannot do at all if it crashes: sensing battery
and position, keeping time, advertising the drone over BLE, and, crucially,
beaconing the drone's last position over LoRa if the Pi goes silent. It is
specified by `Instructions_MD_files/03_ESP32_AUX_FIRMWARE.md` ("file 03") and
lives in `firmware/aux1/`.

## The hardware

- **Seeed Studio XIAO ESP32-C3** microcontroller.
- **INA3221** triple-channel current/voltage monitor over I2C, measuring the
  two flight batteries (Battery A on channel 1, Battery B on channel 2, with
  100 milliohm shunts).
- **GPS module** (TinyGPS++, 9600 baud) for position and time.
- **RFM95 LoRa radio** (915 MHz) for the fallback beacon.
- Connected to the Pi over native USB CDC serial at 115200 baud.

It is a PlatformIO project (`firmware/aux1/platformio.ini`) with pinned library
versions; the pin map is in `firmware/aux1/src/main.cpp`.

## The pin map, and a real bench bug

The pin assignments follow file 03's corrected table. One assignment is a
recorded bench finding worth knowing about, because it looks wrong until you
know the story:

- **LoRa MISO is on D0 (GPIO2), not D9.** File 03's original table put MISO on
  D9. On the first fully-soldered module, SPI reads from the RFM95 failed on D9
  and worked on D0 (`LoRa.begin()` returned false on D9, true on D0). Confirmed
  and reproduced on the bench 2026-07-13. Every other pin in the table was
  correct. This is logged in `docs/CHANGES.md` item 10; the consequence is that
  every XIAO signal pin is now allocated (D0 is no longer the documented spare).

## The state machine

The firmware runs a simple, one-way-per-boot state machine (non-blocking,
`millis()`-based, so GPS parsing never stalls):

```
INIT  ->  NORMAL  ->  FALLBACK
                       (stays until power cycle)
```

- **INIT**: bring up the sensors, GPS, LoRa, and BLE.
- **NORMAL**: the healthy state. Every 5 seconds it sends the Pi a JSON line
  with the latest GPS and battery. It sets the Pi's clock on the first GPS fix
  and on re-fixes (the Pi's aux bridge applies it). It accepts inbound commands
  from the Pi (a keep-alive ping, the last message summary to cache, LoRa
  transmit requests, a BLE payload update, a node id). It advertises over BLE.
  It receives LoRa packets and forwards them to the Pi.
- **FALLBACK**: entered when the Pi goes silent. The rule: after a 60 second
  startup grace period, if no ping has arrived from the Pi for 15 seconds, the
  Pi is presumed dead. In FALLBACK, BLE advertising stops, and every 30 seconds
  the module transmits a compact `FB|` pipe-delimited beacon over LoRa (kept
  under 255 bytes, with pipes sanitised out of the cached content) carrying the
  node id and last known position. It keeps reading GPS and receiving LoRa. It
  stays in FALLBACK until the module is power-cycled, which is deliberately the
  simplest thing to reason about.

The FALLBACK beacon is what lets a neighbouring node report a dead drone as
DEGRADED at its last position (chapter 04), rather than the drone vanishing
from the operation entirely.

## LoRa

- 915 MHz, spreading factor 7, bandwidth 125 kHz.
- Transmit power is set to the **library minimum**, pending clearance for the
  regulated band (a note in the code cites the master plan requirement to keep
  TX power minimal until the spectrum regulator, TRCSL, clears it). The next
  team must not raise TX power without that clearance.
- Received packets starting with `FB|` are forwarded to the Pi as a
  `fallback_rx` event (that is a peer drone's fallback beacon); other packets
  are forwarded as generic `lora_rx` with RSSI and SNR.

## BLE

- NimBLE, non-connectable advertising, one project-fixed 128-bit service UUID:
  `2b57461c-1c04-49c4-944a-13643c1618da`. The local name is `RESCUE-x`.
- The service UUID is put in the advertising packet's **complete-services
  list** (AD type 0x07), and the `nodeId|ssid` payload goes in the scan-response
  service data. This split matters: the emergency app filters scans by service
  UUID *list*, so a UUID present only in service *data* is never matched. This
  was a real bug found in Phase 2 and is the reason the emergency app can detect
  a drone at all (chapter 10).

## The serial protocol

The link to the Pi is newline-delimited JSON, symmetric:

- Module to Pi: `gps` + `battery` snapshots every 5 s, `gps_time` on a fix,
  `fallback_rx` / `lora_rx` on LoRa receive.
- Pi to module: `ping` (keep-alive), `last_msg` (a message summary to cache,
  truncated to 100 chars and stored in flash so it survives a reboot),
  `lora_tx`, `ble_update`, `set_node_id`.

The Pi side of this protocol is `backend/aux_bridge.py` (chapter 06). A pure
software simulator, `tools/aux_sim.py`, speaks the same protocol so the aux
bridge and the firmware can be developed and tested without the other side
present.

## Building and flashing

`firmware/aux1/windows_bringup.html` (a browsable runbook) and
`firmware/aux1/TESTS.md` (six bench tests) are the step-by-step guides. In
short, with PlatformIO:

```
cd firmware/aux1
pio run                 # compile
pio run -t upload       # flash the XIAO over USB
pio device monitor      # watch the serial output
```

The compile was verified clean (231 objects, zero warnings, RAM 7.5% / Flash
43.9%).

## Where the code lives

- Firmware: `firmware/aux1/src/main.cpp`
- Build config and pinned libs: `firmware/aux1/platformio.ini`
- Bench tests: `firmware/aux1/TESTS.md`
- Bring-up runbook: `firmware/aux1/windows_bringup.html`
- The Pi side of the serial link: `backend/aux_bridge.py`
- The simulator: `tools/aux_sim.py`
