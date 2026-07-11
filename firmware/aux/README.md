# firmware/aux: ESP32-C3 unified aux module firmware (file 03)

One firmware image for both aux modules (Seeed XIAO ESP32-C3). Board
identity is provisioned per module over serial
(`{"type":"set_node_id","node_id":"DRONE_A"}`), so a single binary serves
the fleet, mirroring the SSID-configurability fix on the Pi side.

What it does (design v3 sections 3.1-3.4):

- NORMAL mode: feeds GPS + INA3221 battery data to the Pi as newline JSON
  every 5 s over native USB CDC (115200), offers GPS time for the Pi
  clock, relays lora_tx payloads, caches the newest message to flash,
  advertises over BLE (service UUID
  `2b57461c-1c04-49c4-944a-13643c1618da`, service data `nodeId|ssid`).
- FALLBACK mode (no Pi ping for 15 s, 60 s grace at boot): stops BLE,
  transmits the design v3 `FB|...` pipe-format beacon over LoRa every
  30 s carrying position, both battery readings, and the cached last
  message. One-way per boot by design.
- Always: listens on LoRa; `FB|` packets forward to the Pi as
  fallback_rx, everything else as lora_rx.

## Build: PlatformIO (recommended, reproducible)

```
pip install platformio
cd firmware/aux
pio run              # build
pio run -t upload    # flash over USB-C
pio device monitor   # serial at 115200
```

Exact library versions are pinned in platformio.ini.

Verified 2026-07-11: `pio run` compiles clean (231 objects, zero
warnings/errors in this codebase; RAM 7.5%, Flash 43.9% of the XIAO
ESP32-C3's budget). The only earlier failures were the toolchain download
breaking mid-transfer on a slow connection, not a code issue; a retry
loop resolved it. `pio run -t upload` and the bench tests in TESTS.md are
still pending real hardware.

## Build: Arduino IDE alternative

1. Boards manager: esp32 by Espressif Systems 2.x (platform
   espressif32@6.9.0 bundles Arduino core 2.0.17; select
   "XIAO_ESP32C3").
2. Tools > USB CDC On Boot: Enabled.
3. Library manager, install EXACTLY: LoRa 0.8.0 (Sandeep Mistry),
   TinyGPSPlus 1.0.3 (Mikal Hart), ArduinoJson 7.2.1 (Benoit Blanchon),
   NimBLE-Arduino 1.4.3 (h2zero).
4. Open src/main.cpp as the sketch.

## Regulatory note (master plan R1)

LoRa TX power is pinned to the library minimum (2 dBm) in code until the
TRCSL 915 MHz question is resolved. Range testing above minimum power is
blocked on that clearance; record any TX power used in docs/test_log.md.

## Pin map

See the table at the top of src/main.cpp (single source of truth; the
corrected com_module_gps mapping, not the superseded com_module_lora one).

## Bench tests

TESTS.md, six tests. Log results in docs/test_log.md.
