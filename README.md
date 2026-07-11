# Rescue Drone Mesh: Phase 2 monorepo

Disaster-area communication system: drone-mounted Raspberry Pi nodes form
a delay-tolerant 2.4 GHz IBSS mesh while each serves victims and rescuers
on its own always-on 5 GHz access point. Phase 2 adds dual-radio
operation, the ESP32-C3 aux module (GPS, battery telemetry, LoRa
fallback, BLE discovery), decentralized personnel auth, and a
threat-model-driven security pass.

The authoritative specifications are in
[Instructions_MD_files/](Instructions_MD_files/) (00 master plan, 01-08
work packages, 09 security architecture). Decisions and figure changes
are tracked in [docs/CHANGES.md](docs/CHANGES.md); tests are logged in
[docs/test_log.md](docs/test_log.md).

## Layout

| Folder | Contents | Spec |
|--------|----------|------|
| backend/ | FastAPI node software: victim portal (HTTP 80), authenticated API (HTTPS 8443), sync daemon, aux bridge; pytest suite in backend/tests/ | 02, 09 |
| backend/archived/ | retired Phase 1 switcher.py and ble_discovery.py with reasons | - |
| deploy/ | scripted node build: setup_node.sh, fleet CA, systemd units, nftables, VERIFY.md | 01, 09 |
| firmware/aux/ | ESP32-C3 unified firmware (PlatformIO) + bench TESTS.md | 03 |
| tools/ | aux_sim.py, local_two_node_test.sh, aux_bridge_pty_test.py, db_count_check.sh | 02/03/07 |
| docs/ | CHANGES.md, test_log.md, DRONE_LINK.md | - |
| (planned) shared_dart/, gcc_app/, rescue_app/, emergency_app/ | packages 04/05/06 land in later milestones | 04-06 |

Phase 1 evidence lives untouched in the original repos (local-server,
rescue-personnel-app), excluded from this repo by .gitignore.

## Quick start (development, no hardware)

```
cd backend
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt -r requirements-dev.txt
.venv/bin/pytest tests/ -q          # API + sync conflict suite
cd .. && tools/local_two_node_test.sh          # two full nodes on loopback
backend/.venv/bin/python tools/aux_bridge_pty_test.py   # aux bridge vs fake module
```

## Deploying a real node

See [deploy/README.md](deploy/README.md): one `make_fleet_ca.sh` per
fleet, one `setup_node.sh a|b|s` per Pi, then work through
[deploy/VERIFY.md](deploy/VERIFY.md).

## Security model in one paragraph

Threat-model first (file 09): the victim plane is open HTTP by design
with validation and per-IP + global write caps; every replicated record
is HMAC-signed and verified at sync; the rescue/HQ plane runs HTTPS with
certs issued by a fleet CA that the apps pin; per-purpose keys
(K_msg/K_sync/K_token) are HKDF-derived from one master secret so a leak
of one purpose forges nothing else; presence beacons carry persisted
monotonic counters against replay; the MAVLink port on the system drone
is firewalled to expected sources with MAVLink 2 signing to follow in
package 08. Secrets are generated at deploy time and never committed.
