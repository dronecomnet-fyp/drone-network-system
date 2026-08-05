# Testing and results: what to measure, how, and what to write

Companion to `docs/REPORT_AUDIT.md`. This covers Chapter 6 of the report:
what testing already exists, what performance figures the project needs,
exactly how to obtain each one, and how to present results without
overclaiming.

## The problem with the current Chapter 6

It says the integration tests "have been fully designed but have not yet
been executed and recorded on deployed hardware". That was true when
written and is not true now. The fleet has been assembled, run, and
tested with users, and that round produced eighteen findings recorded in
`docs/FIELD_BACKLOG.md`.

The chapter therefore needs restructuring around what actually happened
rather than what was planned:

```
6.1  Test strategy: three levels and why
6.2  Automated tests (243 tests, no hardware)
6.3  Bench verification
6.4  Field testing and results          <- mostly new
6.5  Performance measurements           <- entirely new, see Part 2
6.6  What testing changed about the design
6.7  Threats to validity
```

Section 6.6 is the one examiners remember. Keep it.

---

# Part 1: what already exists

## 1.1 Automated test inventory

Run everything:

```bash
cd backend && .venv/bin/pytest -q                  # 91 passed
cd gcc_app && flutter test                         # 90 passed
cd rescue_app && flutter test                      # 16 passed
cd emergency_app && flutter test                   # 23 passed
cd shared_dart && dart test                        # 23 passed
```

**243 automated tests.** Every one runs with no hardware attached, which
is the point: the fleet is not always available, and a test that needs a
drone does not get run.

### Backend, 91 tests in 10 files

| File | Tests | What it protects |
|------|-------|------------------|
| `test_api.py` | 20 | Both planes, personnel lifecycle, token forgery/expiry, rate limits, health, sync endpoints |
| `test_mission_config.py` | 12 | Stock options on an un-pushed node, content fingerprint stability, stale push refused, app and portal serving identical labels |
| `test_sync_conflicts.py` | 10 | Per-table conflict rules, tampered records rejected, beacon replay rejected |
| `test_conversations.py` | 10 | Victim replies, device-scoped read |
| `test_degraded_and_peers.py` | 9 | DEGRADED derived from live evidence, not read back from a stored flag |
| `test_enrolment.py` | 7 | A carried record verified like a synced one; enrolment blob never carries the PIN, sign-in code deliberately does |
| `test_area_map.py` | 6 | Positions only, never content or ids |
| `test_lora_log.py` | 6 | Log replicates, duplicates collide, forgery rejected, pruning works |
| `test_mission_scoped_creds.py` | 6 | Credentials rejected by a node on another mission |
| `test_sync_resilience.py` | 5 | One failing table cannot stop the others |

### GCC, 90 tests in 9 files

| File | Tests | What it protects |
|------|-------|------------------|
| `mission_state_test.dart` | 20 | Mission round-trip, legacy plan import, module attachment rule, operator intent persistence |
| `ai_advisor_test.dart` | 16 | Parsing good/fenced/prose/refusal replies; validator polygon, count, connectivity, clamp; intent reaching the prompt |
| `mav_service_test.dart` | 14 | MAVLink wire encodings: arm, force-disarm, motor test, takeoff, reposition, RTL |
| `mention_test.dart` | 10 | @ picker text surgery and ordering |
| `portal_config_test.dart` | 10 | Portal option fingerprints |
| `fleet_state_test.dart` | 8 | Lifecycle transitions, reserve-battery maths, recall |
| `draft_visibility_test.dart` | 6 | An unapproved plan never reaches the operations map |
| `app_state_test.dart` | 4 | Settings and credential state |
| `shell_smoke_test.dart` | 2 | Every tab renders its honest empty or gated state |

### Apps, 62 tests

- `rescue_app` 16: login gate, session expiry, data models, and the
  sign-in QR decoder.
- `emergency_app` 23: BLE payload parsing, auto-open cooldown, auto-open
  delivery wiring, local storage.
- `shared_dart` 23: models plus live tests against real backend
  processes, including the certificate-pinning drill.

## 1.2 Three tests worth describing individually

Do not list all 243. Pick the ones where the test itself is the argument.

**`draft_visibility_test.dart`** encodes a safety property, not a
preference: an unapproved AI plan must never appear on the operations
map, and withdrawing approval must actually withdraw it. The reasoning is
that a proposal drawn beside a live operation is indistinguishable from a
decision, and this proposal came from a language model that has never
seen the ground.

**`test_sync_resilience.py`** exists because of a latent defect found
while chasing a field problem: a broad failure in an optional
peer-health cache could abort the whole sync cycle. The cache is a
nice-to-have sitting in front of the thing the system exists for, and it
must never be able to stop it.

**`signin_code_test.dart`** tests that a shipping label, an asset tag,
and a URL are all rejected with a readable message. Scanning the wrong
barcode is the normal case, not the exceptional one.

---

# Part 2: performance measurements

This is what the report is missing, and what "real performance" means for
this project. Each measurement below gives the method, the equipment, the
expected value with its source, and the table to fill.

**Ground rules for every measurement:**

- Record the date, node ids, firmware and git commit, and the power
  source used. The power source is not optional detail: see M7.
- Run three trials minimum. Report each trial and the median, not just an
  average.
- If a result contradicts a design assumption, that is the result. Report
  it.
- Label every derived figure with a confidence level: High (measured and
  reproduced), Moderate (measured once, or measured under conditions
  unlike deployment), Low (estimated or from a datasheet).

## M1. User access point range

**Question:** how far from a node can a victim still submit a message?

**Method:** one node powered on mains or a 3 A supply, at 1.5 m height in
open ground. Walk away in a straight line with a phone. Every 10 m up to
50 m, then every 25 m: record RSSI (Android Wi-Fi settings or a scanning
app), whether the captive portal loads, and whether a submission
succeeds. Continue until three consecutive failures. Repeat on three
bearings.

**Equipment:** two phones (one Android for RSSI), a measuring wheel or a
GPS app, a printed recording sheet.

**Expect:** the 5 GHz AP will be the shortest range in the system.
Somewhere in the 40 to 120 m band in open ground, considerably less
through buildings. Confidence Low before measurement.

| Distance (m) | RSSI (dBm) | Portal loads | Submit OK | Notes |
|---|---|---|---|---|
| 10 | | | | |
| 20 | | | | |
| 30 | | | | |
| 50 | | | | |
| 75 | | | | |
| 100 | | | | |

**Report as:** a plot of success rate against distance, with the usable
range defined as the last distance where three of three submissions
succeeded.

## M2. Mesh backbone range between nodes

**Question:** how far apart can two nodes be and still sync?

**Method:** node A fixed. Carry node B away on the same power discipline.
At each distance, create a message on B, wait two sync cycles (60 s), and
check it appears on A. Record `iw dev wlan1 link` signal on both ends.

**Critical:** run `iw dev wlan1 info` at every point before concluding
anything about range. A missing interface is a power failure, not a range
limit, and mistaking one for the other cost an evening once already.

| Distance (m) | Signal A (dBm) | Signal B (dBm) | Beacon seen | Sync in 2 cycles | wlan1 alive |
|---|---|---|---|---|---|
| 50 | | | | | |
| 100 | | | | | |
| 200 | | | | | |
| 300 | | | | | |

**Expect:** the 2.4 GHz AR9271 with its own antenna should beat the 5 GHz
AP substantially. Confidence Low before measurement.

## M3. Sync convergence time

**Question:** how long does a message take to reach the far side of the
fleet?

This is the headline DTN number and the report currently has nothing like
it.

**Method:** three nodes in range of each other. Submit a message on
DRONE_A through the captive portal, noting the wall-clock time.
Poll DRONE_B and DRONE_S with `curl -sk https://10.99.0.x:8443/health`
every second and record the first moment the message count increases.
Twenty trials.

Repeat for the **two-hop case**: place B out of range of A, but in range
of S, so the message must travel A to S to B.

| Trial | A to B (s) | A to S (s) | Two-hop A to B via S (s) |
|---|---|---|---|
| 1 | | | |
| ... | | | |
| median | | | |

**Expect:** with `SYNC_INTERVAL = 30 s`, a one-hop median near 15 s
(uniformly distributed within the cycle) and a worst case near 30 s.
Two-hop should be roughly double. **If the measurement matches that
model, say so explicitly**, because it demonstrates the mechanism behaves
as designed rather than by luck. Confidence Moderate for the prediction.

## M4. Fallback detection latency

**Question:** how quickly does the fleet notice a node has died, and how
long until the operator sees it?

**Method:** three nodes running, GCC joined to A. Cut power to **the Pi
only** on node B, leaving its aux module powered, noting the time.
Record: time until the aux module enters FALLBACK (its first beacon), time
until A logs `FALLBACK_BEACON`, time until the GCC shows B as degraded,
and time until the Degraded tab shows the carried message. Five trials.

Then restore power and record the time until B returns to NORMAL and
disappears from the degraded list.

| Trial | Aux enters fallback (s) | Neighbour hears (s) | GCC shows degraded (s) | Recovery after restore (s) |
|---|---|---|---|---|
| 1 | | | | |

**Expect:** fallback entry after roughly 15 s of missed heartbeats, first
beacon immediately after, `FALLBACK_EXPIRY` 120 s governing how long it
stays flagged, and recovery after three consecutive pings at 5 s
intervals. Confidence Moderate.

## M5. LoRa fallback beacon range

**Question:** how far away can a dead node still be heard?

**Method:** one aux module forced into fallback, one node receiving. Same
walk-away protocol as M1. Record RSSI and SNR from the receiving node's
`lora_events` table (`GET /lora-events` now gives you these directly,
which is what the table was built for).

**Constraint that must be stated in the report:** transmit power is
deliberately set to the library minimum, not the module's +20 dBm rating,
pending TRCSL confirmation for 915 MHz. **Measure at minimum power and
say so.** A range figure at an unconfirmed transmit power is not a figure
you can defend.

| Distance (m) | RSSI (dBm) | SNR (dB) | Beacon decoded | Notes |
|---|---|---|---|---|

## M6. Message throughput and capacity

**Question:** how many victims can one node handle?

**Method:** script concurrent submissions to `POST /message` from several
devices, or with `curl` in a loop from a laptop on the node's AP. Measure
accepted per second, rejected by rate limiting, and response latency.
Then verify a legitimate rescuer can still log in and claim during the
flood, which is the property that actually matters.

| Concurrent submitters | Accepted/s | Rate-limited/s | p50 latency (ms) | Rescuer still works |
|---|---|---|---|---|
| 1 | | | | |
| 5 | | | | |
| 20 | | | | |

**Also report database growth:** submit 1000 messages and record the
SQLite file size, so the report can state how long a node's storage
lasts. This is a straightforward and useful number nobody has yet.

## M7. Battery runtime, measured against the calculation

**This is the most important measurement in the project**, because the
existing Chapter 4 figures are calculated and the one field observation
so far contradicted the assumption behind them.

**Method for Battery A:** node fully assembled, running all services,
with a victim device connected and syncing to a peer. Log battery voltage
from `/health` every 60 seconds. Run until clean shutdown at the 7.0 V
cutoff. Record actual elapsed time.

**Do this twice: once on the battery pack, once on a 3 A supply**, and
compare. The point is not just the runtime but whether the node stays
healthy, which is what failed before.

**At every sample, also record `iw dev wlan1 info` success.** The failure
mode already observed is the adapter disappearing under load, and a
runtime figure taken while the mesh radio was silently dead is worthless.

| Time (min) | Batt A (V) | Batt B (V) | wlan1 alive | Peers seen | Services OK |
|---|---|---|---|---|---|
| 0 | | | | | |
| 30 | | | | | |
| 60 | | | | | |

**Report against the prediction:**

| Figure | Calculated | Measured | Difference |
|---|---|---|---|
| Battery A runtime, 2S 2500 mAh prototype | 1 h 49 m | | |
| Battery B fallback runtime, 1S 1500 mAh | 8 h 51 m | | |

**Method for Battery B fallback:** put the aux module into fallback with
the Pi off and let it beacon until it dies. This is a long test, run it
overnight. It is also the test that validates the entire dual-battery
justification, so it is worth the time.

## M8. Aux module measurement accuracy

**Question:** are the reported battery figures true?

**Method:** compare the INA3221's reported voltage against a multimeter
at the battery terminals, at five points across the discharge. Do this
for both channels.

| Nominal | Multimeter (V) | INA3221 reported (V) | Error (V) | Error (%) |
|---|---|---|---|---|

**Also verify the phantom-battery case:** disconnect Battery B entirely
and confirm the node reports it as absent rather than as 4.18 V. That is
field backlog #8 and it needs `BATT_B_PRESENT` set correctly in firmware.

## M9. GPS acquisition time

**Method:** cold start with the antenna outdoors and clear sky. Time from
power-on to first valid fix, and to the clock switching from `relative`
to `gps` in `/health`. Five trials cold, five warm.

**Expect:** the NEO-6M datasheet says 27 s cold. Compare measured against
datasheet; the difference is a legitimate finding either way.

## M10. End-to-end latency, victim to rescuer

**Question:** how long from a victim tapping SEND to a rescuer seeing it?

This is the number that answers "does the system work", and it composes
several of the above.

**Method:** victim phone on DRONE_A submits. Rescuer phone on DRONE_B has
the app open. Record the total wall-clock time until the message appears
in the rescuer's list. Twenty trials. Break the total into: submission,
sync convergence (M3), and the rescue app's 5 s poll interval.

| Trial | Total (s) | Notes |
|---|---|---|

**Report as a stacked breakdown**, so the reader can see where the time
goes and that most of it is the deliberate 30 s sync interval rather than
inefficiency.

---

# Part 3: field results already obtained

Do not present the August 2026 session as a footnote. Structure it as a
proper results section: what was tested, what was found, and what
changed.

## 3.1 The session

Eighteen findings from a session with the operator and testers, recorded
in `docs/FIELD_BACKLOG.md` with status tracking. All eighteen are now
closed. Categorise them in the report as the backlog does: critical (3),
bugs (7), user experience (5), design decisions (3).

## 3.2 The three findings that were not what they appeared to be

This is the most interesting material in the whole testing chapter,
because it is about diagnosis rather than coding.

**"Two drones are not syncing."** Several software theories were
investigated and disproved by the nodes' own logs and cursor values. The
cause was hardware: DRONE_B's AR9271 had browned out and dropped off the
USB bus, so `wlan1` did not exist and the IBSS cell could not form. A
phone charger fixed it immediately.

Two lessons for the report: check whether the interface exists before
investigating sync logic; and a node with no peers logs `SYNC_OK` with
`imported=0`, which is indistinguishable from healthy.

**"Auto-open does not work."** No defect in that path. Tests now drive
the same callback the radio drives and confirm correct behaviour in all
three states. The real cause was a different bug: the watch toggle did
not work until Bluetooth was cycled, so no scan ran and no sighting ever
arrived. A feature that is never reached looks identical to a broken one.

**"The Nodes tab never shows peers."** Correct behaviour with no peers to
show, on top of an empty-state message that could not be distinguished
from a hardware failure. Fixed by making the empty state name both
possibilities and give the command that separates them.

**The generalisation worth stating:** most reported bugs were about not
being able to tell two situations apart, not about wrong computation.
That is an interesting finding about diagnostic design in systems that
are expected to be partially disconnected.

## 3.3 Design changes caused by testing

| Finding | Change | Why it matters |
|---|---|---|
| Popups stacked endlessly with two drones | Per-node cooldown | The single-most-recent-sighting comparison was correct with one drone and wrong with two |
| A node marked DOWN forever after one beacon | DEGRADED derived from live evidence | A stored flag cannot be corrected by reality |
| Portal version counter kept desynchronising | Counter deleted, content hash instead | Two earlier fixes patched symptoms; the third asked what the mechanism was for |
| Battery B read 4.18 V unconnected | Explicit present flag | Firmware cannot distinguish a floating input from a full cell by voltage |
| Credentials only worked at the issuing drone | Enrolment plus scan sign-in | DTN means "sync will fix it" can mean never |

---

# Part 4: threats to validity

Include this. It is short and it inoculates against obvious criticism.

- **Fleet size.** Three nodes. Conflict resolution and convergence are
  verified at n=3; behaviour at larger n is argued, not measured.
- **The drones do not fly.** All testing is with nodes on the ground or
  held. Range figures at altitude would be better and are unmeasured.
- **Power was not representative in early tests.** Some results predate
  the discovery in 3.2 and were taken on a supply that could not sustain
  the node. State which results those are.
- **One test session, one location, one weather condition.** Range
  figures in particular are site-specific.
- **Testers were not disaster victims.** Usability findings come from
  team members and the operator, under no stress and in no danger. The
  captive portal changes were driven by reasoning about stress conditions
  rather than by observing them.
- **LoRa is at minimum transmit power** pending regulatory confirmation,
  so range figures are a lower bound, not the system's capability.

---

# Part 5: how to present results honestly

Four rules that will improve the chapter's credibility more than any
extra measurement:

**State the source of every number.** Measured, calculated, or from a
datasheet. Mixing the three without labels is the most common way an
otherwise good results chapter loses trust.

**Attach a confidence level** to anything derived. The project already
uses High / Moderate / Low as a convention; keep it.

**Report the trials, not just the mean.** Three numbers and their median
is more convincing than one average, and it costs one table row.

**When a measurement contradicts the design, lead with it.** The power
finding is the strongest material in the chapter precisely because it
went against the calculation. A results chapter where everything confirms
the design reads as a results chapter where nothing was really tested.

---

# Appendix: running the automated suites for a screenshot

For evidence in the report, capture the terminal output of:

```bash
cd backend && .venv/bin/pytest -q | tail -3
cd gcc_app && flutter test 2>&1 | tail -3
```

Both print a pass count and nothing else on success, which is exactly
what a figure caption needs. Include the date and the git commit hash
alongside, so the figure can be reproduced.
