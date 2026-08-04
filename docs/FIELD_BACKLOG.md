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
| 12 | Watch toggle does nothing until Bluetooth is cycled off and on | TODO |
| 8 | Battery B reads 4.18 V with no battery connected at all | TODO |

## Bugs

| # | Finding | Status |
|---|---------|--------|
| 5 | Map goes blank when zoomed in far | TODO |
| 6 | Nodes tab shows only the directly connected drone, never peers | TODO |
| 15 | Saving a mission creates a NEW file every time instead of saving over the chosen one | TODO |
| 17 | A rescuer can only be issued credentials while on the SAME drone as the GCC. They must be able to sign up mid-mission from a different drone | TODO |
| 18 | Live Ops figures do not refresh: revoking a rescuer leaves the tracked count unchanged | TODO |
| 10 | Auto-open on drone sighting: option exists in Settings but appears not to work | TODO |
| 2 | Mission planning lets a module be attached to a drone AND a drone to a module; the two directions are not filtered properly | TODO |

## User experience

| # | Finding | Status |
|---|---------|--------|
| 3 | Mission planning is not logical or friendly: area should be chosen FIRST and then become the map focus; the shaded area should not be permanently drawn; resources should be cards/chips with images and drag-and-drop rather than lists | TODO |
| 3b | AI suggest should show its progress step by step (thinking, analysing components, applying to map) and place markers progressively, blinking until approved | TODO |
| 3c | Unapproved AI placements must appear ONLY in the planning tab, never on the main Map tab until approved | TODO |
| 11 | Victim app SOS should use selectable options and share location by default, matching the rebuilt captive portal | TODO |
| 13 | Degraded drones need their own tab logging every LoRa message, with blinking map markers, filters for what shows on the map, and automatic clearing when the Pi comes back | TODO |
| 14 | GCC message composer should let the operator attach objects with an @-style picker: degraded drones, other drones, victims | TODO |

## Design decisions needed before coding

| # | Finding | Status |
|---|---------|--------|
| 1 | Physical power switch, startup beep, status LEDs, and a periodic beep while in LoRa fallback. Needs a component list and wiring plan | DISCUSS |
| 4 | The operator must place the GCC position themselves, mark the direction of advance, and mark highly suspected areas. The AI cannot infer these | DISCUSS |
| 7 | Captive portal options: ship defaults, allow editing ONCE during mission planning, then publish. Current build allows repeated pushes | DISCUSS |

## Notes on specific items

### 7, on "only once"

The current design lets the operator push portal options to a node as many
times as they like, and compares content fingerprints so re-pushing the
same thing is harmless. The request is to allow editing once per mission.
Worth confirming what the constraint is protecting against before building
it, because a mission that changes character (a flood that becomes a
landslide) is a real case where a second edit is the correct thing to do.

### 13, on recovery

The aux module already returns to NORMAL after three consecutive pings and
stops beaconing (CHANGES.md item 31), and /health already stops reporting a
node as degraded once it is a live peer again. What is missing is the
operator-facing side: a place that logs the LoRa traffic itself, and map
markers that stop blinking when the node recovers.
