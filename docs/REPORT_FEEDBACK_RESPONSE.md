# Responding to the supervisor feedback on the report

Point by point. Most of it is good and should be taken as written. Two
items rest on premises that are no longer true, and one would put a
factual error into the report if followed literally.

Read the three flagged items first, because they change what you should
do with the rest.

---

## FLAG 1: "field tests are planned rather than executed" is out of date

The feedback repeatedly works from the draft's own statement that the
integration tests "have been fully designed but have not yet been
executed". That was true when the draft was written. **It is not true
now.**

Two tester rounds have happened on the assembled fleet:

| Round | Date | Findings | Status |
|-------|------|----------|--------|
| 1 | 2026-08-03 | 18 | all closed, `docs/FIELD_BACKLOG.md` |
| 2 | 2026-08-09 | 12 | in progress, `docs/FIELD_BACKLOG_2.md` |

Thirty findings from real use, plus a fleet bring-up that surfaced five
distinct hardware and configuration faults.

**This changes the advice in feedback item 5.** You were told to reframe
the unconducted field tests as "the next phase of Hardware-in-the-Loop
integration". Do not do that: it would understate the work. You have
executed field testing, it produced results, and several of those results
are more interesting than the tests that passed.

What is genuinely still outstanding is **quantitative measurement**:
range, battery runtime, sync convergence timings. That distinction is the
honest framing:

> Functional field validation has been carried out across two tester
> rounds. Quantitative characterisation of range and endurance remains
> outstanding and is described in Section 7.3.

`docs/REPORT_TESTING.md` has the ten measurement procedures for the part
that genuinely is outstanding.

## FLAG 2: do NOT add BATMAN-adv or MQTT

Feedback item 4 says to "explicitly define BATMAN-adv and MQTT as the
industry standards you've chosen for reliability".

**This system uses neither.** I checked the whole source tree. The only
occurrence anywhere is a symbol name inside a compiled firmware map file,
which is a build artifact, not a dependency.

What the system actually uses:

| Layer | What it really is |
|-------|-------------------|
| Mesh | IEEE 802.11 IBSS (ad-hoc), a fixed cell, static addressing. No mesh routing protocol at all |
| Node discovery | Custom signed UDP presence beacons, port 48555 |
| Data movement | Pull synchronisation over HTTPS with per-table delta cursors |
| Messaging | No broker. There is no MQTT, and no publish/subscribe anywhere |

Adding those names would be a factual error in an examined document, and
it is exactly the sort of claim an examiner may probe.

**What to do instead**, which answers the real concern behind the
comment. The reviewer is asking why you did not use standard components.
That is a good question and it has a good answer, so write it as a
justification rather than a false claim:

> A mesh routing protocol such as BATMAN-adv was considered and not
> adopted. Such protocols maintain routes across a connected topology,
> whereas this network is intentionally and frequently partitioned: the
> design assumption is that nodes are usually NOT in contact. Routing
> tables have nothing to converge on when there is no path, so the system
> uses a store-carry-forward model instead, in which a node holds data
> until it next meets a peer. Similarly, a broker-based protocol such as
> MQTT presumes a reachable broker, which reintroduces the single point
> of failure the project exists to avoid.

That paragraph turns a weakness into evidence of judgement, and it is
true.

## FLAG 3: the test count is 263, not 243

The draft's number is stale and so is the one in the feedback. Current,
verified by running them:

| Suite | Tests |
|-------|-------|
| backend (pytest) | 104 |
| gcc_app | 90 |
| shared_dart | 28 |
| emergency_app | 23 |
| rescue_app | 18 |
| **Total** | **263** |

Regenerate this table on the day you submit. It has moved four times this
week.

---

# The rest, point by point

## 1. Reframe Chapter 6 as "Validation and Verification"

**Accept the rename.** It is more accurate than "Testing and Results",
because the chapter covers both formal verification (automated tests) and
validation against real use (tester rounds).

**Accept "logic over physics", and strengthen it.** The reviewer's
instinct is right and understates what you have. Suggested opening:

> The system's logical core is verified by 263 automated tests that run
> without any hardware. These cover the parts that are hardest to observe
> in the field: per-table conflict resolution during synchronisation,
> personnel authentication and revocation across nodes, resilience of the
> sync daemon to a single failing table, and the rule that an unapproved
> AI proposal can never appear on the operations map. Hardware testing
> then validates what only hardware can: radio behaviour, power, and
> human use under stress.

That last sentence is the important one. It says why the split exists
rather than treating the automated tests as a substitute.

**Accept moving the notable test cases earlier**, and add a fourth. The
three you have are good; a stronger set:

- The sign-in QR decoder rejecting a shipping label, because scanning the
  wrong barcode is the normal case rather than the exceptional one.
- `draft_visibility_test.dart`, which encodes a safety property: a
  proposal from a language model must never be mistakable for a decision.
- `test_sync_resilience.py`, written after finding that an optional cache
  could abort the whole sync cycle.
- **New:** `test_audit_sanitise.py`, which proves a LoRa beacon payload
  cannot forge an audit log entry. This is a genuine security test on the
  one path an attacker can reach without touching your network.

## 2. Strengthen the volunteer drone narrative

**Accept entirely.** This is the best single piece of feedback and the
framing is right: the modular kit is the most novel thing in the project.

Use the suggested abstract sentence, with one adjustment for accuracy.
The reviewer wrote "within minutes"; say what is actually true:

> The system demonstrates a "Zero-Access" integration model in which any
> volunteer drone becomes a network relay by carrying a self-contained
> module, with no access to, or modification of, the host aircraft's
> flight software.

"Zero-Access" is defensible and worth defining precisely early on: the
module shares nothing with the aircraft but a mounting point and, at
most, power. It does not read the flight controller, does not use the
aircraft's radio, and cannot affect flight.

**Accept the Chapter 2 to 3 signpost**, and note it is directly supported
by your own literature review: Chandran and Vipin identify deployment
strategy as an open problem, which is precisely what a hardware-agnostic
kit addresses.

## 3. Signposting in Chapter 5

**Accept the four-service intro.** Correct as described. Verify the
wording against reality: embedded C++ firmware, a Python sync daemon, two
FastAPI services (not one, since the victim plane and the authenticated
plane are separate processes on separate ports), and three Flutter
applications sharing one Dart package.

That correction matters, because the two-service split IS the security
architecture and blurring it weakens Chapter 5.8.

**Accept highlighting 5.1.1.** Also add the outcome, which the draft
does not yet have: the portal was rebuilt around tappable options after
testers pointed out that typing is the one thing a person in a disaster
cannot reliably do. That turns a design rationale into a validated design
rationale.

## 4. Visual and structural consistency

**Accept the figure cross-references.** Mechanical but effective.

**Reject the BATMAN-adv and MQTT item.** See Flag 2.

**Accept fixing the `[?]` placeholders.** Do not, however, replace them
with a vague gesture at "standard industry practices" if the sentence is
making a specific factual claim, because that reads as evasion to an
examiner. Two better options: cut the sentence, or rewrite it so it no
longer needs a citation. A claim about your own system needs no citation
at all.

## 5. Conclusion

**Accept "synthesise, do not summarise".**

**Adjust the specific wording.** The reviewer suggests saying you
"validated the eventual consistency model through automated logic
testing". You can now say something stronger and still true, because the
mesh has actually run:

> The eventual consistency model was verified logically by automated
> conflict-resolution tests, and then demonstrated on the assembled
> fleet, with two nodes synchronising eight replicated tables across an
> ad-hoc link.

**Reframe item 5's "future work" pivot.** See Flag 1. The honest split is
functional validation done, quantitative characterisation outstanding.

---

# What I would add that the feedback does not mention

Three things you have that the draft does not use, and any one of them
would strengthen it more than the cosmetic items above.

### A diagnosis chapter, or a strong section

Across two tester rounds and a fleet bring-up, several reported faults
turned out not to be what they appeared to be:

- "Two drones are not syncing" was a USB power brownout.
- "Auto-open does not work" was a different bug upstream: no scan was
  ever running.
- "The Nodes tab never shows peers" was correct behaviour with no peers,
  plus an empty state that could not be told from a hardware failure.
- "Fallback is broken" was, at minimum, a five-minute suppression window
  that every reboot armed.

**The generalisation is a finding in its own right:** in a
partition-tolerant system, most reported faults were an inability to tell
two situations apart, not incorrect computation. A node with no peers
logs `SYNC_OK` and looks perfectly healthy. That is a real observation
about observability in delay-tolerant systems and it is the kind of thing
an examiner remembers.

### The measured result that contradicted the design

Chapter 4 calculates battery runtime and presents it as verified. Field
testing showed the arrangement could not reliably power a node at all:
the USB WiFi adapter browned out and dropped off the bus. Reporting a
calculation that reality refuted is stronger than reporting one that was
never tested.

### A security finding you have not written up

Audit log lines quoted content arriving over LoRa. A newline in that
content would start a new line in the log, so anyone able to transmit on
915 MHz could forge entries such as a fabricated login. Found, fixed, and
covered by a test. It belongs in Chapter 5.8 as a real vulnerability
found by inspection on the one path an attacker can reach without
touching the network.

---

# Priority, if time is short

1. **Flag 2**, remove or reframe BATMAN-adv and MQTT. Prevents a factual
   error.
2. **Flag 1**, correct the "not executed" framing throughout Chapter 6.
   Currently understates the work.
3. **Abstract and Chapter 2 signpost.** Small edits, large effect.
4. **Chapter 6 rename and reordering.**
5. Placeholder citations.
6. Figure cross-references, the last and most mechanical.
