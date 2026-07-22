# 17 Glossary

Terms and acronyms used across this project, in plain language.

## Networking and the mesh

- **DTN (Delay-Tolerant Network):** a network that does not assume a permanent
  end-to-end link. Nodes sync whenever they meet and store-and-forward messages.
  The core property of this system (chapter 04).
- **Store-and-forward:** a node holds a message and passes it on to the next node
  it meets, so the message reaches its destination even when the source and
  destination are never in range at the same time.
- **IBSS (Independent Basic Service Set):** Wi-Fi ad-hoc mode, where devices form
  a peer network with no access point. Our 2.4 GHz drone-to-drone backbone.
- **BSSID:** the 48-bit identifier of a Wi-Fi cell. We fix it
  (`02:12:34:56:78:9A`) so all nodes join one IBSS cell and it does not split.
- **AP (Access Point):** normal Wi-Fi infrastructure mode. Our 5 GHz `RESCUE_x`
  that phones connect to.
- **Node:** one drone-mounted Raspberry Pi running the backend. The fleet is
  DRONE_A, DRONE_B, DRONE_S.
- **Fleet:** the set of nodes.
- **Presence beacon:** a small signed UDP broadcast a node sends every 10 s so
  peers know it is there (chapter 04).
- **Pull sync:** a node fetches new rows from a peer using a `since` cursor
  (chapter 04).
- **Captive portal:** the mechanism that makes any hostname a joined phone
  requests resolve to the node, so the victim form appears automatically.

## Roles and identity

- **Victim:** a member of the public in the disaster area; uses the emergency app
  or the captive portal; anonymous (random device id).
- **Rescuer / RESCUE_TEAM:** a field responder; logs into the rescue app with a
  PIN.
- **HQ:** a headquarters operator; a personnel role with elevated permissions;
  uses the GCC.
- **GCC (Ground Control Center):** the operator's desktop app (chapter 08).
- **Personnel:** the record of a rescuer or HQ operator (id, role, PIN hash,
  status).
- **Session token:** a stateless HMAC-signed credential any node can verify
  offline (chapter 05).
- **Break-glass key:** the static HQ API key, demoted to a labelled recovery
  credential for a fresh fleet with an empty personnel table.

## Security

- **HKDF:** a key-derivation function. We use HKDF-SHA256 to derive three
  purpose keys from one master secret (chapter 05).
- **K_MSG / K_SYNC / K_TOKEN:** the three purpose-separated keys: record signing,
  inter-node auth and beacon signing, and token signing.
- **HMAC:** a keyed message authentication code; how records, beacons, and tokens
  are signed.
- **PBKDF2:** the slow hash used to store PINs.
- **Fleet CA (Certificate Authority):** the one authority that signs every
  node's TLS certificate; the apps trust only it (real pinning).
- **Evil twin:** a rogue access point impersonating a node; defeated by fleet-CA
  pinning.
- **Plane:** one of the five trust domains the security model is organised around
  (chapter 05).

## Drone and flight

- **System drone / DRONE_S / AeroSync 5:** the one drone with a flight controller
  the GCC commands (chapter 11).
- **Volunteer drone:** a third-party drone carrying one of our comm modules; its
  flight is its own pilot's job.
- **CC3D Open Revolution Mini:** the flight controller on DRONE_S.
- **MAVLink:** the standard drone telemetry and command protocol.
- **MAVLink gateway:** the Python bridge on DRONE_S's Pi that forwards MAVLink
  between the flight controller's serial and a UDP socket (chapter 11).
- **Heartbeat gate:** the rule that a command is allowed only while a MAVLink
  heartbeat has arrived within the last 2 seconds.
- **RTL (Return To Launch):** the command that sends a drone home; issued by the
  recall button and the battery watchdog.
- **Props off:** propellers removed; the mandatory state for all bench flight
  testing in this phase.

## Hardware

- **AR9271:** the USB Wi-Fi adapter (ath9k_htc driver) used for the IBSS mesh; one
  of the classic IBSS-capable adapters.
- **Aux module:** the ESP32-C3 board on each drone that senses battery/GPS,
  advertises BLE, and beacons over LoRa if the Pi dies (chapter 07).
- **ESP32-C3 (Seeed XIAO):** the microcontroller of the aux module.
- **INA3221:** the triple-channel battery voltage/current monitor.
- **LoRa:** a long-range, low-bandwidth radio (915 MHz here) used for the
  fallback beacon.
- **BLE (Bluetooth Low Energy):** how a drone advertises itself to the emergency
  app; done by the ESP32 with a fixed service UUID.
- **RFM95:** the LoRa radio module.

## Software and process

- **Node backend:** the FastAPI application(s) and daemons on each node
  (chapter 06).
- **Schema v3:** the Phase 2 database schema (chapter 06).
- **shared_dart / rescue_mesh_shared:** the shared Dart package of models and the
  API client for the apps.
- **MissionState:** the GCC object holding the whole operation as a local JSON
  file (chapter 12).
- **FleetState:** the GCC fleet manager (chapter 11).
- **DEMO / REAL mode:** the two fleet-manager modes: simulated drones vs the real
  DRONE_S MAVLink path.
- **Milestone (M1-M7):** the implementation phases; M7 is the mission layer.
- **Work package (files 01-08):** the eight specification documents, one per part
  of the system.
- **Runbook:** a browsable, gated, step-by-step field procedure (chapter 14).
- **MBTiles:** the offline map tile file the GCC uses (there is no internet at a
  deployment).
- **TRCSL:** the spectrum regulator whose clearance is required before raising
  LoRa transmit power (chapter 07).
