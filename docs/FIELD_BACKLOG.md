# Field backlog: tester findings, 2026-08-03

Roughly twenty findings from a testing session with the operator and
testers. Recorded verbatim in intent so nothing is lost, grouped by what
they actually are, because "bug" and "improvement" need different handling
and some of these are design decisions rather than defects.

Status key: TODO, DOING, DONE, DISCUSS (needs a decision before code).

## Critical: makes something unusable

| # | Finding | Status |
|---|---------|--------|
| 9 | Victim app pops the "drone nearby" screen over and over, stacking many screens | DONE |
| 12 | Watch toggle does nothing until Bluetooth is cycled off and on | DONE |
| 8 | Battery B reads 4.18 V with no battery connected at all | DONE, needs reflash |

## Bugs

| # | Finding | Status |
|---|---------|--------|
| 5 | Map goes blank when zoomed in far | DONE |
| 6 | Nodes tab shows only the directly connected drone, never peers | TODO |
| 15 | Saving a mission creates a NEW file every time instead of saving over the chosen one | DONE |
| 17 | A rescuer can only be issued credentials while on the SAME drone as the GCC. They must be able to sign up mid-mission from a different drone | DONE |
| 18 | Live Ops figures do not refresh: revoking a rescuer leaves the tracked count unchanged | DONE |
| 10 | Auto-open on drone sighting: option exists in Settings but appears not to work | TODO |
| 2 | Mission planning lets a module be attached to a drone AND a drone to a module; the two directions are not filtered properly | DONE |

## User experience

| # | Finding | Status |
|---|---------|--------|
| 3 | Mission planning is not logical or friendly: area should be chosen FIRST and then become the map focus; the shaded area should not be permanently drawn; resources should be cards/chips with images and drag-and-drop rather than lists | TODO |
| 3b | AI suggest should show its progress step by step (thinking, analysing components, applying to map) and place markers progressively, blinking until approved | TODO |
| 3c | Unapproved AI placements must appear ONLY in the planning tab, never on the main Map tab until approved | TODO |
| 11 | Victim app SOS should use selectable options and share location by default, matching the rebuilt captive portal | DONE |
| 13 | Degraded drones need their own tab logging every LoRa message, with blinking map markers, filters for what shows on the map, and automatic clearing when the Pi comes back | DONE |
| 14 | GCC message composer should let the operator attach objects with an @-style picker: degraded drones, other drones, victims | TODO |

## Design decisions needed before coding

| # | Finding | Status |
|---|---------|--------|
| 1 | Power switch, startup beep and lights, on the Pi. Parts list, wiring and code in docs/NODE_PANEL.md | DONE, needs soldering |
| 4 | Operator places the GCC on the map, then draws one or more ARROWS for the direction they expect to advance and CIRCLES for suspected areas, all feeding the AI | DECIDED |
| 7 | Portal options: ship defaults, operator may edit them ONCE per mission, then publish | DECIDED |

## Notes on specific items

### 7, decided: edit once per mission

Defaults ship on every node. If the operator never edits them, that is what
victims see. They may edit the option list ONCE per mission, and then push.

The operator's reasoning, which settles an earlier disagreement: keeping
multiple revisions in play makes "which options is this node actually
serving" hard to reason about, and that ambiguity is worse than the
flexibility. Recorded because it overrides my suggestion that a mission
changing character (a flood becoming a landslide) justifies a second edit.

Note this is a lock on EDITING, not on pushing. Pushing still happens once
per node, because the operator has to join each drone in turn.

### 1, decided: on the Pi, minimal scope

Buzzer and lights move to the Raspberry Pi rather than the aux module. That
also sidesteps the blocker: every XIAO signal pin is already allocated
(CHANGES.md item 10), so there was no free GPIO for a buzzer there.

Scope is a physical power switch for the whole node, plus a beep and lights
when it comes up. The periodic beep during LoRa fallback is dropped.

Consequence worth stating: because this lives on the Pi, it CANNOT indicate
anything when the Pi is dead, which is exactly the fallback case. The aux
module keeps that job over LoRa, silently.

### 4, decided: place, then draw intent

Mission planning gains a "place GCC" action that opens the map for a single
tap. The operator then draws one or more arrows for the direction they
expect to advance, and circles for areas they suspect need attention. All
of it is fed to the AI advisor, which cannot infer any of it.

### 17, decided: scan only, no typing

The rescuer scans ONE QR code shown by the GCC and is signed in. No PIN is
typed. The code carries the signed personnel record and the PIN together,
so the phone can hand the record to whichever drone it is standing next to
before logging in, which is what makes signup work on a drone that has
never heard of that person.

Carrying the PIN inside the QR is a deliberate weakening, and it is only
defensible because credentials are scoped to a mission: activating a
different mission in the GCC retires every credential issued under the old
one. The PIN login path stays as the fallback for a cracked camera or a
printed code that will not scan.

### 13, on recovery

The aux module already returns to NORMAL after three consecutive pings and
stops beaconing (CHANGES.md item 31), and /health already stops reporting a
node as degraded once it is a live peer again. What is missing is the
operator-facing side: a place that logs the LoRa traffic itself, and map
markers that stop blinking when the node recovers.
