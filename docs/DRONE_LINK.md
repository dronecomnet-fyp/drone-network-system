# DRONE_LINK: system drone flight controller identification (file 04 Stage 0)

Status: NOT DONE. This file is filled in on the bench, props off, before any
drone-control code is written (file 04 Stage 0 is a mandatory gate; the
hardware doc says the Revo Mini firmware is unconfirmed).

To record here during Stage 0:

1. Revo Mini over USB: which GCS talks to it (try in order: Mission Planner
   for ArduPilot/MAVLink, Betaflight Configurator for MSP, LibrePilot GCS
   for UAVTalk). Firmware name and version string.
2. ESP32-WROOM bridge: serial banner and baud rate, firmware identity
   (DroneBridge exposes a WiFi AP and web UI if present).
3. Receiver type (PPM / SBus / per-channel PWM): the ArduPilot Revo Mini
   page states RC input needs PPM or SBus, verify what the drone has.
4. Chosen FC target and flashing outcome (recommended: ArduPilot ArduCopter
   per master plan D5, official support for Revo Mini: High confidence,
   https://ardupilot.org/copter/docs/common-openpilot-revo-mini.html).
5. FC telemetry UART to Pi wiring choice and baud (file 08 hardware
   checklist item 5).
6. MAVLink 2 signing (file 09 plane 4): SETUP_SIGNING outcome, and whether
   the chosen GCC-side MAVLink library supports signing. If it does not,
   record the residual risk and the compensating nftables layer here.
