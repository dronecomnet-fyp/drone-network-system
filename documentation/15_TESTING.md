# 15 Testing and Verification

The project has three kinds of verification: automated tests that run with no
hardware, the acceptance drills that run on the assembled fleet, and the
browsable runbook gates. This chapter tells you what exists and how to run it.
The integration test plan is `Instructions_MD_files/07_INTEGRATION_TESTS_AND_DEMO.md`
("file 07") and the running log is `docs/test_log.md`.

## Automated tests (no hardware needed)

### Backend (pytest)

From `backend/` with the virtualenv:

```
.venv/bin/python -m pytest tests/ -q
```

91 tests covering both planes and the sync layer:

- `tests/test_api.py`: the victim message flow and signature; the check-in flow
  (SOS creates a message); the full auth lifecycle (create personnel including
  HQ role, login, token-authenticated call, revoke, reject); wrong-PIN rate
  limiting; token forgery, expiry, and a token naming a nonexistent person all
  rejected; announcements; the rescuer location heartbeat (post, read, identity
  from token, validation, break-glass refused); and that the victim plane has no
  read-back endpoints.
- `tests/test_sync_conflicts.py`: the per-table conflict rules (CLAIMED beats
  NEW, personnel newest-wins with REVOKED override, append-only tables,
  personnel-location newest-wins), tampered records rejected at ingest, and
  beacon replay rejected by the counter.
- `tests/test_sync_resilience.py`: one failing table must not stop the others,
  and the optional peer-health cache must never abort a sync cycle. Written
  after a latent defect where a broad failure in a nice-to-have cache could
  have stopped messages replicating entirely.
- `tests/test_degraded_and_peers.py`: DEGRADED is DERIVED from live evidence,
  so a single fallback beacon cannot mark a node down forever while the fleet
  is actively syncing with it.
- `tests/test_enrolment.py`: a carried personnel record is verified the same
  way a synced one is; the enrolment blob never contains the PIN, while the
  sign-in code deliberately does (chapter 05 states why).
- `tests/test_mission_scoped_creds.py`: credentials issued under one mission
  are rejected by a node running another, and an unconfigured node accepts any.
- `tests/test_mission_config.py`: stock options on an un-pushed node, content
  fingerprints stable across identical pushes, a stale push refused, and the
  app and the captive portal serving the SAME labels.
- `tests/test_conversations.py` and `tests/test_area_map.py`: victim replies
  and the positions-only area map (no content, no ids).
- `tests/test_lora_log.py`: the LoRa log replicates to a node that never heard
  the beacon, the same frame coming back does not duplicate, a forged entry is
  rejected, and the table is pruned rather than growing without bound.

### GCC app (flutter test)

From `gcc_app/`:

```
flutter analyze     # clean
flutter test        # 90 tests
```

Covering mission serialization (round-trip, legacy plan import, the
module-attachment rule, and the operator's intent drawing surviving a save and
load), the fleet state machine and the reserve-battery math, the MAVLink wire
encodings (arm, force-disarm, motor test, takeoff, reposition, RTL), the AI
advisor (parsing good/fenced/prose/refusal replies, the validator's
polygon/count/connectivity/system-drone/clamp checks, and that operator intent
reaches the prompt), the @ attach picker (the text surgery, and the picker's
priority ordering), the draft-visibility rule, plus a shell smoke test that
every tab renders its honest empty or gated state and that the break-glass key
unlocks the HQ surfaces.

Two of those exist because writing them found something. The @ picker's text
surgery left a double space when attaching mid sentence. And the
draft-visibility tests pin a safety property, not a preference: an unapproved
plan must not appear on the operations map, and withdrawing approval must
actually withdraw it.

### Shared package and the phone apps

- `shared_dart`: `dart analyze` is clean; it has live tests that run against
  real backend processes, including the certificate-pinning drill.
- `rescue_app`: 16 tests, including the sign-in QR decoder. That decoder is
  tested on its own because scanning the WRONG barcode is the normal case, not
  the exceptional one: shipping labels, asset tags and food packaging all carry
  codes, and every one must produce a readable message rather than a crash on
  the login screen.
- `emergency_app`: 23 tests, including the BLE payload parser, the auto-open
  cooldown (two drones alternating must open twice, not forever), and the
  auto-open WIRING: a sighting opens the screen when the setting is on, does
  nothing when off, and does nothing before the person has been asked. That
  last group was added because a tester reported auto-open as broken when the
  real cause was upstream, and a setting stored correctly but never consulted
  looks identical to a broken feature.

### Website

From `website/`: `npm run build` must be clean.

### The aux firmware and the gateway

- `firmware/aux1`: `pio run` compiles clean; the six bench tests are in
  `firmware/aux1/TESTS.md`.
- `mavlink_gateway`: a pty-based test exercises byte-exact forwarding and the
  telemetry tap with no hardware (`tools/mavgw_pty_test.py`).
- The aux bridge: a pty test drives it against the simulator
  (`tools/aux_bridge_pty_test.py`, `tools/aux_sim.py`).

## The two-node sync test

`tools/local_two_node_test.sh` (and the pytest conflict tests) run two
backend instances on loopback with separate databases and ports, peered by
explicit unicast, and assert convergence of all tables, CLAIMED precedence,
personnel revocation propagation, replayed-beacon rejection, and no duplicates
after a mid-sync kill. This is the DTN correctness check without radios.

## The security drills (T9)

File 07's test T9 is the set of security acceptance drills, run on the fleet:

- **T9.1** certificate pinning: an evil-twin access point with its own
  certificate is rejected by the apps (the fleet-CA pinning). Verified in the
  `shared_dart` live tests.
- **T9.2** token forgery: forged, expired, and ghost tokens rejected (backend
  suite).
- **T9.3** beacon replay: a replayed presence beacon rejected by the counter
  (sync tests).
- **T9.5** flood control: per-IP and global write caps enforced.
- **T9.6** repo hygiene: no secret material committed; a fresh clone plus the
  setup script yields a working node with fresh keys.
- Plus the unsigned-MAVLink residual-risk note (chapter 11) and the
  physical-capture / rotation drill.

## Acceptance runbooks (on the fleet)

The browsable runbooks (chapter 14) each end their stages in a gate: a readout
of what to expect and a "stop here" if it does not match. `deploy/VERIFY.md` is
the per-node acceptance checklist, and `deploy/mission_layer_check.html` is the
eight-gate end-to-end check of the mission layer (product site, GCC spec fetch,
AI planner, rescuer tracking, fleet demo and real, live ops).

## How to run everything at once (a pre-commit sanity sweep)

```
# backend
cd backend && .venv/bin/python -m pytest tests/ -q
# gcc
cd ../gcc_app && flutter analyze && flutter test
# shared
cd ../shared_dart && dart analyze
# rescue + emergency
cd ../rescue_app && flutter analyze
cd ../emergency_app && flutter analyze
# website
cd ../website && npm run build
# repo hygiene: no em dashes in tracked source
cd .. && git ls-files | grep -vE 'node_modules|\.png|\.jpg|\.mbtiles' | xargs grep -lP '[\x{2014}]' 2>/dev/null
```

The last line should print nothing (no literal em dash characters; the runbooks
use the `&mdash;` HTML entity, which is allowed).
