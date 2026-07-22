# Rescue Drone Mesh: Engineering Handbook

A disaster-area communication network carried by drones. When the cellular
network is down, our drone-mounted Raspberry Pi modules rebuild a local
network on the spot so victims can call for help and rescue teams can
coordinate. This handbook explains the whole system: what it does, how it is
built, why each decision was made, and where every piece of code lives.

## Who this is for

- **Team members** who need to understand a part of the system they did not
  build themselves.
- **The next students** who take the project over. Read it front to back
  once, then use it as a reference. By the end you should be able to rebuild
  a node from a blank SD card, run the apps, extend the backend, and know
  what is left to do.

You are expected to know basic Python, Dart/Flutter, Linux, and networking.
Everything specific to this project is explained here.

## How this handbook is organised

Read in order the first time; the later chapters assume the earlier ones.

| # | Chapter | What it covers |
|---|---------|----------------|
| 01 | [Introduction](01_INTRODUCTION.md) | The problem, the idea, the two project phases, the team and handover context |
| 02 | [Architecture Overview](02_ARCHITECTURE_OVERVIEW.md) | The whole system on one page: nodes, apps, drone, the five security planes, data flow, and the repository map |
| 03 | [From Phase 1 to Phase 2](03_PHASE1_TO_PHASE2.md) | What Phase 1 built, its documented gaps, and exactly how and why Phase 2 fixed each one (time-slicing to IBSS, BLE, sync, auth) |
| 04 | [The DTN Mesh Network](04_DTN_MESH_NETWORK.md) | The two-radio design, IBSS backbone, user access point, addressing, presence beacons, pull sync, store-and-forward |
| 05 | [Security Architecture](05_SECURITY.md) | The threat model, HKDF key separation, record signing, certificate pinning, PIN login and session tokens |
| 06 | [The Node Backend](06_BACKEND.md) | The FastAPI node software: the two planes, schema v3, models, the sync engine and daemon, the aux bridge |
| 07 | [The Aux Module Firmware](07_FIRMWARE_AUX.md) | The ESP32-C3 sensor and fallback module: battery/GPS, LoRa fallback beacon, BLE advertising |
| 08 | [The Ground Control Center App](08_GCC_APP.md) | The Windows desktop operator app: every tab, state management, the map, live ops |
| 09 | [The Rescue Personnel App](09_RESCUE_APP.md) | The rescuer phone app: login, requests, claims, HQ uplink, location heartbeat |
| 10 | [The Emergency (Victim) App](10_EMERGENCY_APP.md) | The public app: privacy-first check-ins, BLE drone discovery, SOS |
| 11 | [The System Drone and Flight Control](11_SYSTEM_DRONE.md) | DRONE_S, the MAVLink gateway, the fleet manager (demo and real), and the safety policy |
| 12 | [The Mission Layer](12_MISSION_LAYER.md) | Mission planning, the AI deployment advisor, rescuer tracking, and the live operations picture |
| 13 | [The Product Website](13_PRODUCT_WEBSITE.md) | The Supabase-backed product site, unit IDs, and how the app fetches specs |
| 14 | [Deployment and Operations](14_DEPLOYMENT_OPERATIONS.md) | Building a node from scratch, secrets and the fleet CA, systemd units, the firewall, and the runbooks |
| 15 | [Testing and Verification](15_TESTING.md) | The automated test suites, the acceptance drills, and how to run everything |
| 16 | [Design Decisions](16_DESIGN_DECISIONS.md) | The significant decisions, each with what was chosen, why, and what was rejected |
| 17 | [Glossary](17_GLOSSARY.md) | Every acronym and project-specific term |
| 18 | [Handover and Future Work](18_HANDOVER_FUTURE_WORK.md) | What is done, what is left, and a roadmap for the next team |

## The source of truth

This handbook is the explanatory layer. The authoritative artefacts it
explains are, in order of precedence:

1. **The code**, in the monorepo at the repository root.
2. **`Instructions_MD_files/00-09`**: the original work-package specifications
   (00 master plan, 01-08 packages, 09 security). This handbook narrates and
   connects them; it does not replace them.
3. **`docs/CHANGES.md`**: the running log of every decision that changed an
   earlier figure, with reasons. Chapter 16 curates the important ones.
4. **The runbooks** under `deploy/` and `docs/` (browsable HTML): the exact
   step-by-step field procedures with verification gates.

When this handbook and the code disagree, the code wins; then please fix the
handbook.

## Conventions used here

- Code is cited as `path/file.py` or `path/file.dart:function`, relative to
  the repository root, so you can jump straight to it.
- Technical figures carry a confidence label (High / Moderate / Low) when
  they are estimates rather than measured or specified values.
- We do not use the em dash character anywhere in this project's text; that is
  a hard writing convention, not a style preference.
- "The fleet" means the set of drone nodes (DRONE_A, DRONE_B, DRONE_S).
