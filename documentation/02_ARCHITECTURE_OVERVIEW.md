# 02 Architecture Overview

This chapter is the whole system on one page. Later chapters zoom into each
box.

## The physical picture

```
        VICTIM phone                RESCUER phone              GCC laptop
        (any Wi-Fi)                 (rescue app)               (desktop app)
             |                           |                          |
             |  join RESCUE_x 5 GHz AP   |  join RESCUE_x 5 GHz AP   | join RESCUE_x
             v                           v                          v
     +-------------------------------------------------------------------+
     |                       ONE DRONE NODE (Raspberry Pi 4)             |
     |                                                                   |
     |   wlan0 (onboard)  ->  5 GHz user AP  RESCUE_x at 10.42.0.1       |
     |   wlan1 (AR9271)   ->  2.4 GHz IBSS mesh at 10.99.0.x  <----------+---> other
     |   aux (ESP32-C3)   ->  battery/GPS sensing + LoRa fallback beacon |     nodes
     |   [DRONE_S only]   ->  USB to CC3D flight controller (MAVLink)    |
     +-------------------------------------------------------------------+
                                     |
                        DTN mesh (10.99.0.0/24): the three
                        nodes DRONE_A/B/S sync whenever in range
```

Each node has two Wi-Fi radios doing two different jobs, plus a small aux
microcontroller. The 5 GHz side is what people connect to; the 2.4 GHz side is
the drone-to-drone backbone. Chapter 04 explains why the split, and why the
backbone is IBSS (ad-hoc) rather than the Phase 1 single-radio time-slicing.

## The nodes

| Node | User AP | Mesh IP | Special role |
|------|---------|---------|--------------|
| DRONE_A | RESCUE_A | 10.99.0.1 | plain node |
| DRONE_B | RESCUE_B | 10.99.0.2 | plain node |
| DRONE_S | RESCUE_S | 10.99.0.3 | also a MAVLink gateway to the flight controller |

All three run the identical node software and the identical setup script; they
differ only by a per-node config file (`deploy/nodes/drone_[a|b|s].conf`).

## The software, layer by layer

### On each node (the backend)

Two web services, on purpose (this is a security decision, chapter 05):

- **The victim plane** (`backend/http_app.py`, plain HTTP on port 80): the
  captive portal and the victim message form. Open by necessity; a victim
  cannot be asked to trust a certificate.
- **The authenticated plane** (`backend/api.py`, HTTPS on port 8443): every
  rescuer/HQ/sync operation. TLS with a fleet-CA-issued certificate that the
  apps pin to.

Behind them:

- `backend/models.py`: the SQLite database (schema v3) and all record
  signing/verification.
- `backend/sync_engine.py` and `backend/sync_daemon.py`: the DTN sync. The
  daemon broadcasts presence beacons and, on a schedule, pulls new rows from
  every peer it can see; the engine verifies each record's signature and
  applies per-table conflict rules.
- `backend/aux_bridge.py`: talks to the ESP32-C3 over serial, feeding battery,
  GPS, and time into the node, and receiving LoRa fallback events.
- `backend/crypto_keys.py`: derives the three purpose-separated keys from one
  master secret.

### On the drones (firmware)

`firmware/aux1/src/main.cpp`: the ESP32-C3 aux module. It reports battery
(INA3221) and GPS, sets the Pi clock from GPS time, and if the Pi goes quiet it
drops into a fallback state and beacons the node's last position over LoRa so
the drone stays locatable. It also advertises a fixed BLE service UUID so the
emergency app can detect a nearby drone.

### The shared Dart package

`shared_dart/` (`rescue_mesh_shared`): the data models and the API client used
by all three Flutter apps, so the wire format and the certificate pinning are
written once.

### The three apps

- **GCC** (`gcc_app/`): the operator's Windows desktop app. Map, live
  operations, mission planning, personnel management, drone control. Chapters
  08, 11, 12.
- **Rescue app** (`rescue_app/`): the rescuer's phone. Login, victim requests,
  claims, HQ uplink, location heartbeat. Chapter 09.
- **Emergency app** (`emergency_app/`): the public victim app. Privacy-first
  check-ins, BLE drone discovery, SOS. Chapter 10.

### The product website

`website/`: a React site backed by Supabase presenting the hardware, with a
unique ID per manufactured unit. The GCC looks up a unit's specs by ID.
Chapter 13.

## The five security planes

The whole design is organised around a threat model of five planes, each with
its own trust assumptions (chapter 05 is the full treatment; file 09 is the
spec):

1. **Victim plane** (open by necessity): plaintext HTTP; message integrity is
   protected by signing at ingest, not by transport.
2. **Rescue and HQ plane**: HTTPS with real certificate pinning to the fleet
   CA; PIN login yielding session tokens.
3. **Inter-node plane**: every synced record carries an HMAC signature verified
   on receipt; presence beacons are signed and replay-protected.
4. **Drone control plane** (highest stakes): the MAVLink link, isolated by
   network firewalling; commands gated on a fresh heartbeat.
5. **Physical capture plane**: accepted residual risk, with key rotation as the
   response.

## How data flows: a victim message

1. A victim joins `RESCUE_A`, the captive portal opens, they submit a message
   with their location. `http_app.py` validates it, signs it with K_MSG, and
   stores it in DRONE_A's database (victim plane, port 80).
2. DRONE_A's sync daemon beacons its presence on the mesh. When DRONE_B is in
   range, DRONE_B's daemon pulls DRONE_A's new rows over the authenticated
   plane, verifies each signature, and stores them (marked as synced from A).
   The message is now on both nodes; it propagates onward to any node either of
   them meets. This is DTN store-and-forward.
3. A rescuer on any node logs into the rescue app, sees the message on the
   Requests screen, and claims it. The claim (with the rescuer's identity from
   their session token) syncs back across the fleet so nobody double-responds.
4. The GCC, joined to whichever node is in range, polls that node and shows the
   message on the map with its data age, plus who claimed it.

Every screen shows how fresh its data is, because in a DTN "live" honestly
means "as last synced".

## The repository map

```
Instructions_MD_files/   the Phase 2 specification (00 master, 01-08, 09 security)
backend/                 the node software (FastAPI, SQLite, sync, crypto)
firmware/aux1/           the ESP32-C3 aux module firmware (PlatformIO)
mavlink_gateway/         the DRONE_S serial<->UDP MAVLink bridge (Python)
deploy/                  node setup script, per-node configs, systemd units,
                         firewall, fleet CA, and the browsable runbooks
shared_dart/             the shared models + API client for the Flutter apps
gcc_app/                 the ground control centre desktop app
rescue_app/              the rescue personnel phone app
emergency_app/           the public victim phone app
website/                 the product site (React + Supabase)
docs/                    changes log, mission planning, drone link, releases,
                         offline maps, test log, phone runbook
documentation/           this handbook
tools/                   aux simulator and helper scripts
local-server/            Phase 1 backend (evidence, git-ignored from build)
rescue-personnel-app/    Phase 1 rescue app (evidence)
previous_codes/          Phase 1 misc (evidence)
```

Read chapter 03 next to understand why Phase 2 looks the way it does.
