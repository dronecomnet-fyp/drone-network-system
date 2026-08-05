# Report audit: what is outdated, missing, or inconsistent

Audit of `fyp_report_draft.md` against the code as it stands on 5 August
2026 (`docs/CHANGES.md` item 47).

The draft is well written and the reasoning in it is sound. The problem is
timing: it describes the system as it was around CHANGES item 25 to 29,
and the system has moved a long way since. Most of what follows is
"correct when written, wrong now" rather than "badly written".

**Read this first:** the single most valuable change is Chapter 6. The
draft says field testing has not happened yet. It has, it produced
eighteen findings, and three of them were not the bugs they appeared to
be. That is exactly the kind of material an examiner rewards, and it is
currently absent. `docs/REPORT_TESTING.md` covers that chapter in full.

## Severity key

| Level | Meaning |
|-------|---------|
| **A** | Factually wrong now. An examiner reading the code would catch it |
| **B** | A whole feature that exists and is not in the report at all |
| **C** | Internal inconsistency, broken cross-reference, or contradiction |
| **D** | A number that needs updating |
| **E** | Figure or screenshot that is missing or wrong |

---

## A. Factually wrong now

### A1. Fallback mode is no longer one-way (Sections 3.3.4, 5.3.2)

The draft says, twice and emphatically:

> "The transition from normal operation to fallback mode is intentionally
> one way during a single power cycle... This behaviour is a deliberate
> design choice rather than a missing feature."

**This is now the opposite of what the firmware does.** The aux module
returns to NORMAL automatically after three consecutive heartbeats
(`FALLBACK_IS_TERMINAL = false`, `FALLBACK_RECOVERY_PINGS = 3` in
`firmware/aux1/src/main.cpp`).

Why it changed, which is worth writing up rather than just correcting:
one-way fallback caused a real field bug. A node that recovered from
nothing worse than a service restart kept beaconing over LoRa forever and
stayed marked DOWN in the GCC while the fleet was actively syncing with
it. Recorded as CHANGES item 31.

**Action:** rewrite both sections. The design rationale is now "recovery
must be earned": three consecutive pings, not one, because a single ping
during a crash loop would flap the state.

### A2. There are eight replicated tables, not five

"Five replicated tables" appears in Sections 3.3.5, 5.2.1, 5.2.2, 5.2.3,
5.4.6, 5.8.4, 6.1.1 and 6.2.2. The current set is:

| Table | Conflict rule |
|-------|---------------|
| `messages` | CLAIMED beats NEW; earlier `claimed_at` wins |
| `personnel` | REVOKED beats ACTIVE; else newest `updated_at` |
| `personnel_locations` | newest `updated_at` wins |
| `announcements` | append-only |
| `gs_messages` | append-only |
| `checkins` | append-only |
| `message_replies` | append-only |
| `lora_events` | append-only |

**Action:** global find-and-replace on "five", plus two new rows in the
conflict-rule table, plus a paragraph on why `message_replies` and
`lora_events` replicate while `node_health` deliberately does not. That
contrast is a good exam answer: health is a node's opinion about right
now and travels badly; a heard LoRa frame is a fact about a moment and
travels fine.

### A3. The rescue app does full certificate pinning (Sections 5.5.2, 5.8.3, 5.8.7)

Sections 5.8.3 and 5.8.7 both say the rescue app "validates only the
expected host address rather than the certificate" and call it a known
gap. That was Phase 1 behaviour and it is gone: the app fails closed
without a fleet CA loaded, exactly like the GCC.

Note this also **contradicts Section 5.5.2 of the same draft**, which
correctly describes fleet-CA validation. One of the two is left over.

**Action:** delete the "known limitation" framing from 5.8.3 and 5.8.7.
Keep it in the design-evolution narrative as something that WAS fixed,
because "we found it and closed it" is a stronger story than never having
had the problem.

### A4. Drone control is implemented, not a "preparation interface" (Section 5.6.6)

The draft says the Drone tab "intentionally works as a preparation
interface rather than an active control interface" and "displays the
specific hardware identification steps that must be completed".

The GCC now has a working MAVLink service: live telemetry, arm, disarm,
force-disarm, takeoff, reposition, RTL, all gated on a fresh heartbeat,
with a battery watchdog. `gcc_app/test/mav_service_test.dart` has 14
tests on the wire encodings.

**The policy has not changed and must stay in the report:** props-off
bench verification only. Free flight waits for an explicit safety setup.
That is a scope boundary, not an unimplemented feature, and the
distinction matters.

**Action:** rewrite 5.6.6 as "implemented and bench-verified, deliberately
not flown", and update Section 5.8.3, which says the drone control plane
"has not yet been fully implemented".

### A5. DRONE_S does have a GPS time source (Sections 3.1, 3.3.1, 3.3.3)

The draft says DRONE_S "does not provide its own GPS derived time source"
and "relies on relative timestamps", with MAVLink time sync listed as a
future enhancement.

It is not future work any more. `mavlink_gateway/mav_gateway.py` decodes
`SYSTEM_TIME` and `GPS_RAW_INT` from the flight controller and feeds both
the clock and `/health`.

**Action:** correct all three places. DRONE_S has no AUX MODULE, which is
still true and still explains the missing LoRa fallback and BLE, but it
is no longer time-blind.

### A6. The captive portal is no longer a free-text form (Sections 3.2.1, 5.1)

The draft describes the portal as a form with "a free text description of
their situation". It was rebuilt (CHANGES 34, and again for field backlog
#11) around big tappable option buttons, urgent ones first, with nothing
required to type and location requested automatically as an opt-out.

The reasoning belongs in the report because it is a human-factors
argument, not a technical one: typing is the thing a person in a disaster
cannot reliably do, with wet hands, a cracked screen, a keyboard in the
wrong language, and panic.

**Action:** rewrite 3.2.1 and 5.1. Add the per-mission option config
(Section B4 below).

### A7. The victim plane has read-back endpoints now (Sections 5.1.7, 6.1.1)

The draft states the "no read back principle" as absolute, and Section
6.1.1 cites a test proving "the victim plane does not provide any
endpoint for reading submitted data back".

Three read endpoints now exist on port 80: `/my-conversation/{device_id}`
(a victim reading replies to their own messages), `/area-map` (positions
only), and `/portal-options`.

The principle was not abandoned, it was made precise, and the report
should say so: a victim can read **their own** thread and **positions**,
never another victim's content and never any id. `/area-map` returns
coordinates only, and `backend/tests/test_area_map.py` exists to keep it
that way.

**Action:** restate the principle as scoped rather than absolute. This is
a good discussion point about how a security rule survived contact with a
real requirement.

### A8. Battery B monitoring changed twice, and the report should say so (Section 4.1.6)

Section 4.1.6 is correct as it stands (INA3221 CH1 = Battery A, CH2 =
Battery B). But the route there is worth a paragraph in the design
evolution: Battery B was moved to the ESP32's own ADC (CHANGES 26) and
then moved straight back (CHANGES 30), because measurement showed the
problem the first change solved did not exist.

There is also a field finding not in the report at all: with nothing
connected, the INA3221 input floats near the supply rail and reads about
4.18 V, which is indistinguishable from a healthy full cell by voltage
alone. The firmware now needs an explicit `BATT_B_PRESENT` flag. That is
a genuine measurement limitation and examiners like this kind of detail.

---

## B. Missing entirely

Everything below is built, tested, and in the repository, and appears
nowhere in the draft. Each needs at least a subsection.

### B1. The mission layer (M7) is the biggest gap

Section 5.6.3 describes the GCC map as "advisory markers with a coverage
radius, stored locally". That has grown into an entire milestone:

- **Mission model** (`gcc_app/lib/state/mission_state.dart`): a whole
  operation in one portable JSON file. Identity, area polygon, resource
  inventory, product spec cache, named deployments.
- **Three drone entry paths**: our brand by unit id, volunteer drone with
  one of our modules attached, or minimal. A module cannot be on two
  airframes. The roster is never frozen, so a volunteer arriving on site
  can be added offline.
- **Operator intent**: the operator places the GCC itself, draws advance
  arrows, and circles suspected areas. This is the one planning input
  that exists nowhere else in the system and cannot be inferred from a
  map.
- **The AI deployment advisor**: an OpenAI-compatible client so free
  providers work; the model proposes JSON placements and the GCC
  **validates** them (point-in-polygon, count against available drones,
  mesh connectivity, one system drone, radius clamping). The validator is
  the real guarantee, because free models are unreliable.
- **Draft visibility as a safety property**: an unapproved plan shows in
  planning mode only, blinking, and never on the operations map, because
  a proposal drawn beside a live operation reads as a decision.
- **The fleet manager**: a per-drone lifecycle state machine with a DEMO
  simulator (any number of drones, auto-return on reserve battery) and a
  REAL path for DRONE_S only.

This is easily a chapter section of its own, and it is the part of the
project that goes beyond "a mesh that carries messages".

### B2. Rescuer location tracking (M7d)

New replicated table `personnel_locations`, a battery-conscious
foreground-only heartbeat in the rescue app (90 s, paused when
backgrounded), rescuer markers on the GCC map, and a "Share my location"
toggle. The foreground-only limitation is deliberate and should be stated
as a battery trade-off rather than omitted.

### B3. Victim conversations and the victim area map

- **Replies** (CHANGES 37): rescuers and HQ reply to a victim; replies
  replicate so they reach whichever drone the victim next meets. The
  victim app shows honest delivery states and never claims a human has
  read the message.
- **Area map** (CHANGES 38): victims can see drones, other people who
  need help, and rescuers. Positions only, never content or ids. The
  decision to show other victims to each other was deliberate and is
  worth defending in the report.

### B4. Per-mission victim portal options

`backend/mission_config.py`. The operator edits the option list once per
mission and pushes it to each node in turn. Three points worth writing up:

- Stock options ship on every node, so an un-pushed node still works.
- Every node reports which config it holds, so partial rollout is
  visible instead of silent.
- **There is no version counter.** A counter has to be stored somewhere
  and every holder can be wrong, so a config identifies itself by a hash
  of its own content. This replaced two earlier attempts to patch the
  counter's symptoms and is a good "stop and ask what the mechanism is
  for" story (CHANGES 36).

### B5. Mission-scoped credentials, enrolment, and scan sign-in

- Credentials carry a `mission_id`; a node running a different mission
  rejects them, so activating a new mission retires every old credential
  at once.
- **Enrolment** (`POST /enrol`): a rescuer's phone carries their signed
  personnel record to a node that has never synced with the issuer. It is
  verified through the same path sync uses, so it adds a delivery route,
  not new trust.
- **Scan sign-in**: one QR, no typing. The QR carries the PIN as well as
  the record. **This is a deliberate weakening and the report must say so
  plainly**, including the cost: anyone photographing the code on screen
  has those credentials until the mission ends. It is bounded by mission
  scoping, and confidence that this is tight enough in practice is
  Moderate, because it depends on operators actually switching missions.

Written up honestly this is one of the strongest sections available: a
real security trade-off, made deliberately, with the cost stated and a
confidence label attached.

### B6. The LoRa event log and the Degraded tab

New replicated `lora_events` table logging every LoRa frame a node hears,
with RSSI, SNR, carried position and battery, and the last victim message
the downed node was holding. Feeds a GCC tab showing degraded drones,
recovered drones, and a filterable raw log.

The design point: it replicates because the node that hears a beacon is
whichever one is nearest the failure, and HQ may be joined to a different
one. Pruned to 2000 rows because a node down for a day beacons about 2900
times.

### B7. The product website and Supabase

`website/`: a hosted catalogue with a 3D product view, unit lookup, and
request-a-quote, backed by Supabase with row-level security. The GCC
fetches unit specs by id and caches them into the mission so they resolve
offline afterwards. Anon key public by design, service_role never
committed.

### B8. Field Share (the GCC distribution server)

The ground laptop becomes a local download point for the APKs and offline
map regions over its own Wi-Fi, with a QR code, because at a disaster
site there is no internet and no app store. Plain HTTP for the same
reason as the victim plane.

### B9. The node front panel

Power switch, startup beep, READY and MESH lamps on the Pi
(`docs/NODE_PANEL.md`, `docs/node_front_panel.html`). Belongs in Chapter
4 alongside the enclosure.

Two things make it report-worthy rather than trivia. The amber MESH lamp
makes the USB brownout failure (Section D3) visible instantly instead of
via sync logs. And the panel cannot indicate anything once the Pi is
dead, which is exactly the fallback case: an accepted cost of the aux
module having no free GPIO left.

### B10. GCC usability work

Map layer filters (counting HIDDEN layers, because a filter someone
forgot is how a victim goes unseen), the @ picker for attaching drones
and victims to a message with their coordinates, and the connectivity
detection service. Minor individually, but they evidence iteration in
response to testers.

---

## C. Internal inconsistencies and broken references

| # | Where | Problem |
|---|-------|---------|
| C1 | Contents page | Lists 5.4 Database Design, 5.5 BLE/GPS/LoRa, 5.6 Time Sync, 5.7 Fallback Logic, 5.8 "Security Layer (RSP protocol)", 5.9 Flutter apps. The actual Chapter 5 has a completely different structure. Also "RSP protocol" does not exist anywhere in the system |
| C2 | Contents page | Stops at Chapter 7, but the body repeatedly cites Chapter 8 (limitations) and Chapter 9 (future work) |
| C3 | Chapter 6 throughout | Refers to "Section 7.1", "Section 7.2.1", "Section 7.1.1". Left over from when Testing was Chapter 7 |
| C4 | Section 5.6.7 | Cites "the outstanding alignment issue discussed in Section 5.5.7". **Section 5.5.7 does not exist** (5.5 stops at 5.5.6) |
| C5 | Sections 4.1, 4.1.8, 4.4 | All three cite "Section 4.1.9" for DRONE_S's hardware. **Section 4.1.9 does not exist** |
| C6 | Figure 3.2 caption | Says "user redirected → HTTPS submission page opens → message submitted over TLS". **This directly contradicts the body text**, which explains at length that everything is HTTP. The caption is from the superseded design |
| C7 | Section 5.1 opening | Says http_app.py is "in the **local-server** repository". Section 3.1 says local-server is retired and replaced. It is in drone-network-system |
| C8 | Sections 4.5, 4.6 | Empty headings (Enclosure Design, Mounting System) |
| C9 | Section 3.4 | Only 3.4.1 exists. The Phase 1 to Phase 2 evolution stops after describing Phase 1 |
| C10 | Section 3.2.4 | Says the GCC is "described in Section 3.2.4", which is the section itself |
| C11 | Figure numbering | Chapter 4 runs 4.1, 4.5, 4.6, 4.3, 4.9, 4.10. Out of order with gaps |
| C12 | Section 5.5.5 | Describes Settings as holding "the static API key required for authentication". The API key is the break-glass fallback; PIN login is primary. 5.5.2 says this correctly |

---

## D. Numbers to update

| # | Section | Draft says | Actual |
|---|---------|-----------|--------|
| D1 | 6.1.1, 6.1.4 | Backend suite implied ~28 tests, two files | **91 tests across 10 files** |
| D2 | 6.1.3, 6.1.4 | GCC: app_state, plan_state, shell_smoke | **90 tests across 9 files.** `plan_state_test.dart` no longer exists; it is `mission_state_test.dart` |
| D3 | 4.2 | Battery A runtime 3.62 h design / 1 h 49 m prototype | **The measured field result contradicts the assumption entirely.** See below |
| D4 | 6.1.4 | Rescue app: 2 files | 3 files, 16 tests (adds `signin_code_test.dart`) |
| D5 | 6.1.4 | Emergency app: 2 files | 23 tests, now including auto-open cooldown and wiring |
| D6 | 5.2.3 etc | five tables | eight |

### D3 deserves its own treatment: the power finding

This is the most important measured result the project has, and it is not
in the report.

During field testing two nodes stopped syncing. Several software theories
were investigated and disproved. The actual cause: **DRONE_B's AR9271 had
browned out and dropped off the USB bus**, so `wlan1` did not exist, the
IBSS cell could not form, and the two databases silently diverged.
Swapping to a phone charger fixed it immediately and completely.

What this means for Chapter 4, which currently presents the power design
as verified by calculation:

- The battery arrangement **as tested cannot reliably power a node**. The
  Pi plus the AR9271 (roughly 400 to 500 mA) plus the aux module needs a
  3 A class supply, or the adapter needs a powered hub.
- Section 4.3.2's statement that "the AR9271 does not act as an
  independent load" is arithmetically true but operationally misleading:
  the adapter's current has to pass through the Pi's USB regulation, and
  that path is where it failed.
- The failure is **silent from the application's point of view**. Sync
  kept logging `SYNC_OK` with `imported=0`, which reads as healthy: a
  node with no peers has nothing to import and cannot distinguish
  "nobody has anything new" from "I cannot see anybody".

Confidence: High. It reproduced and the fix was decisive.

Write this up as a measured result that contradicted a design assumption.
It is far more valuable than a runtime calculation that agrees with
itself.

---

## E. Figures and screenshots

### E1. There are no UI screenshots at all, and there should be

Every figure in the draft is a diagram (`image1.png` to `image19.png`).
For a project whose contribution is substantially a set of working
applications, a report with zero screenshots understates the work. An
examiner cannot tell from a block diagram that the software exists.

**Minimum set, 12 screenshots.** Capture at a consistent window size,
light or dark consistently, with realistic but fake data (never real
personal information).

| # | Screenshot | Where it goes | What it must show |
|---|-----------|---------------|-------------------|
| 1 | Victim captive portal, options visible | 3.2.1 / 5.1 | Big tappable buttons, urgent first, nothing to type |
| 2 | Victim portal after submitting | 5.1 | The honest DTN confirmation wording |
| 3 | Emergency app SOS screen | 3.2.5 / 5.7 | Options fetched from the node, location switch on |
| 4 | Emergency app conversation | 5.7 | Delivery states that do not claim a human read it |
| 5 | Emergency app area map | 5.7 | Drones, victims, rescuers as positions only |
| 6 | Rescue app victim requests | 5.5.3 | Claim state, ages, location chips |
| 7 | Rescue app scan sign-in | 5.5 / B5 | The scanner screen, with the QR aiming box |
| 8 | GCC operations map | 5.6.3 | Several layers at once, offline tiles, the layer filter |
| 9 | GCC mission planning | 5.6.3 / B1 | Area polygon, placements with coverage circles, intent arrows |
| 10 | GCC Live Ops | 5.6 / B1 | Stat tiles with data ages, the fleet board |
| 11 | GCC Degraded tab | B6 | A degraded drone with beacon age, RSSI, carried message |
| 12 | GCC Nodes tab | 5.6.4 | Peer cards with two separate ages |

**Strongly recommended extras:** the AI advisor progress dialog mid-run
(evidences the step-by-step honesty argument), the personnel issue dialog
showing the QR with its warning (evidences the security trade-off), and
the front panel lit on a real node (evidences hardware built, not just
designed).

### E2. Hardware photographs

Chapter 4 has diagrams but no photographs. Add: one assembled node with
the enclosure open showing both sub-units, one close-up of the aux module
with GPS/LoRa/INA3221 visible, one of the node mounted on a drone, and
one of the front panel with the lamps lit.

### E3. Result figures that do not exist yet

Chapter 6 will need plots once the tests in `docs/REPORT_TESTING.md` are
run: range against packet loss, battery voltage against time, sync
convergence time, and a fallback detection timeline. These are listed
with their measurement procedures in that document.

### E4. Figure 3.2 must be redrawn

Its caption describes the superseded HTTPS redirect flow (C6).

---

## F. Suggested structural changes

1. **Split Chapter 5.** It currently carries the entire software design
   including security. Consider promoting the security architecture (5.8)
   to its own chapter; it is long enough and it is a strong section.

2. **Give the mission layer its own section** at minimum, ideally a
   chapter alongside the node software. It is the part that distinguishes
   this from a message-relay demo.

3. **Add a "design evolution" thread rather than one section.** The
   project has an unusually good record of decisions that were made,
   tested, and reversed: the version counter, Battery B's two moves,
   one-way fallback, the DEGRADED flag, and a wrongly attributed field
   failure. `docs/CHANGES.md` items 26, 30, 31, 36, 39 and 40 are the raw
   material. Reversals shown with reasons read as engineering maturity,
   not as indecision.

4. **Move the "not yet executed" framing out of Chapter 6.** Field
   testing happened. See `docs/REPORT_TESTING.md`.

5. **Add a limitations subsection on power** (D3), separate from the
   generic limitations chapter, because it changes a design conclusion.

---

## G. What is good and should not be touched

Worth saying, so the rewrite does not damage it:

- The literature review connects each cited work to a specific design
  decision in this project rather than summarising it in isolation. That
  is the right way to do it.
- Section 5.8.1's ranked asset list, with confidentiality deliberately
  last and justified, is a genuinely strong piece of security writing.
- The captive-portal HTTP decision (5.1.1) is well argued.
- Section 6.2's honesty about tests being planned rather than executed is
  exactly the right instinct. Keep the instinct, update the facts.
- The power calculations in 4.2 are methodical and clearly presented.
  They need a measured-result section added, not a rewrite.
