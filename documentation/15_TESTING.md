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

28 tests covering both planes and the sync layer:

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

### GCC app (flutter test)

From `gcc_app/`:

```
flutter analyze     # clean
flutter test        # 41 tests
```

Covering mission serialization (round-trip, legacy plan import, the
module-attachment rule), the fleet state machine and the reserve-battery math,
the MAVLink wire encodings (arm, force-disarm, motor test, takeoff, reposition,
RTL), the AI advisor (parsing good/fenced/prose/refusal replies, and the
validator's polygon/count/connectivity/system-drone/clamp checks), plus a shell
smoke test that every tab renders its honest empty or gated state and that the
break-glass key unlocks the HQ surfaces.

### Shared package and the phone apps

- `shared_dart`: `dart analyze` is clean; it has live tests that run against
  real backend processes, including the certificate-pinning drill.
- `rescue_app` and `emergency_app`: `flutter analyze` reports zero errors and
  zero warnings; unit tests under each app's `test/`.

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
