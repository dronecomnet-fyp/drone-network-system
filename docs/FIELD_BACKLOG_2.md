# Field backlog, round 2: tester findings, 2026-08-09

Twelve findings from the second tester round, after the fleet was brought
up and the mesh verified. Recorded before fixing so nothing is lost, and
graded by whether it stops someone using the system.

Status key: TODO, DOING, DONE, NEEDS HARDWARE (cannot be confirmed
without a bench test).

## Blocking: someone cannot do their job

| # | Finding | Status |
|---|---------|--------|
| 2.1 | AI suggestion leaves a banner with no Close, Approve or Discard. The app has to be restarted | DONE |
| 2.2 | Rescuers can only log in on the node the GCC is joined to, and the QR cannot be scanned | DONE |
| 2.3 | Both mobile apps appear to lose their session when closed and reopened | TODO |

## Bugs

| # | Finding | Status |
|---|---------|--------|
| 2.4 | Degraded tab shows nothing during a real LoRa fallback (Pi unplugged, aux on battery) | DIAGNOSED, retest |
| 2.5 | Battery B shows a changing voltage with the battery physically removed, in several places | DONE, needs configuring per module |
| 2.6 | A reply sent without claiming still shows the victim "the drone has your message" rather than a read state | TODO |
| 2.7 | HQ uplink: the rescue app can send field reports, the GCC has nowhere to read them | TODO |
| 2.8 | Unconfirmed: does a BLE sighting actually raise a notification in the victim app | NEEDS HARDWARE |

## Improvements

| # | Finding | Status |
|---|---------|--------|
| 2.9 | Victim app location logging: on every app open, and much more often once emergency mode is on, including immediately at the moment it is switched on | TODO |
| 2.10 | Mission planning: the operator enters a lot and none of it persists. Needs save, a deploy action, and a reset afterwards | TODO |
| 2.11 | Live Ops should show the current plan as clear numbered steps, each one navigating to the tab that does it | TODO |
| 2.12 | The AI advisor should propose the WHOLE mission layout, not only drone placements | TODO |

---

## Notes on specific items

### 2.1, what actually went wrong

Three mistakes stacked, and any one alone would have been survivable.

The dialog was opened with `barrierDismissible: false` and **no actions**,
relying entirely on the caller to pop it. The caller then switched tabs
while it was open, disposing the Mission screen that owned the context.
The next line was `if (!context.mounted) return;`, so the function
returned before ever reaching the `pop()`.

Fixed at all three layers rather than only the one that failed: the
dialog now always draws its own Close button, the root navigator is
captured before any `await`, and the tab switch happens after the close.
The follow-up summary also gained Approve and Discard.

The general rule taken from it: **a modal must always carry its own exit,
regardless of what the surrounding code intends to do.**

### 2.2, two reports that were one bug

"Rescuers must be on the same node as the GCC" and "nobody can scan the
QR" were the same defect.

`_signin_blob` base64-encoded the record, embedded that string inside
another JSON object, and base64-encoded the result. Double encoding
inflates by a third, giving about 880 characters. That needs QR version
25, which is 117 modules across, and at 220 px that is 1.9 pixels per
module. Phone cameras need at least 3.

So the code never scanned, everyone fell back to typing a PIN, and a PIN
only authenticates on a node that already holds the record. The
cross-node feature was built, tested, and unreachable in the field.

Now the record travels as an object rather than a nested string and the
payload is deflated: about 430 characters, version 15, rendered at 380 px
with the lowest error correction. Roughly 5 pixels per module.

Both ends now assert the **size**, not just correctness. Adding one field
to the personnel record would otherwise quietly break it again.

### 2.4, what the evidence actually showed

The operator's `grep -a FALLBACK_BEACON` returned ten strong beacons,
RSSI -46 to -54, so the radio path and the receive code both work.

Every one of them was dated **2026-08-02**, a week before the test. So
today's attempt produced nothing at all, and the log looked reassuring
only because it holds history and nobody checked the dates.

Three causes, all of them silent, and at least one is self-inflicted:

1. **The shutdown grace window.** A clean shutdown tells the module the
   silence is expected and suppresses fallback. It was set to five
   minutes, and the nodes were being rebooted constantly that day, so a
   test performed shortly after a reboot would produce no beacon at all.
   Reduced to 90 s, which still covers the real case it was written for
   (halt, then reach over and flip the switch) without swallowing tests.

2. **A module power-cycled at the moment of the test.** If it was living
   on USB power from the Pi and Battery B only went on as the test
   started, cutting the Pi reboots it, and after a reboot it waits 60 s
   for a first heartbeat before even starting the 15 s dead-Pi count.

3. **Those old beacons could never have reached the Degraded tab
   anyway.** They predate `lora_events`, so they exist in the audit log
   and in `node_health` but not in the table the tab reads. Correct
   behaviour, and misleading evidence.

The chain has five links and the tab is empty if any one fails: the
module must enter FALLBACK and transmit, a DIFFERENT node must receive it
(a node cannot hear itself), that node must store it, and the GCC must be
joined to a node holding the record.

`docs/FALLBACK_TEST.md` is the procedure that removes the ambiguity:
watch the receiver's log live, know the 15 s and 30 s timings, and check
the dates on anything historical.

### 2.5, why this keeps coming back

An unconnected INA3221 input floats near the supply rail and reads about
4.18 V, which is indistinguishable from a healthy cell by voltage alone.
The firmware needs to be told a battery is absent; it cannot infer it.

Confirmed on the bench. A module with nothing on channel 2 reported
`bat_b_v` drifting between 4.152 and 4.184 V with `bat_b_ma` at 0.8 mA,
while channel 1, pulled to ground, correctly reported null. The existing
plausibility floor of 1.0 V catches a GROUNDED input and cannot catch a
FLOATING one.

The presence flags were compile-time constants, both hard-coded true, so
a module whose wiring differed from the build reported a battery that was
not there and the only remedy was a recompile. They now live in NVS
alongside the node id, are set with `tools/aux_set_battery.py`, and are
reported in the boot line so the operator can see what the module
believes.

This is a per-module setting, not a code fix: after reflashing, each
module still has to be told what is actually fitted.

The finding that it appears "in several places" is the more useful half:
the value is shown on the Nodes tab, in Live Ops, on peer cards, in the
Degraded tab and in the LoRa beacon itself. Whatever the fix, it has to
be at the source, not per screen.

### 2.6, what the victim should see

Current behaviour is correct only while no reply exists: the app says the
drone holds the message, because at that point nobody has read it and
claiming otherwise would be dishonest.

Once a rescuer replies, a human demonstrably has read it, whether or not
they pressed Claim. Replying is stronger evidence of attention than
claiming is. So a reply should move the victim's view to a read state,
and claiming should not be a precondition for that.

### 2.10 and 2.11, treat together

Both are about the mission having a lifecycle rather than being a screen
full of fields. Save, deploy, reset, and a visible sequence of what
happens next. Worth designing as one thing rather than two features.
