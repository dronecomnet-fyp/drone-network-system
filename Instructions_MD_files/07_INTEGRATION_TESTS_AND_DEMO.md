# 07 INTEGRATION TEST PLAN AND EXAMINER DEMO SCRIPT

Run after files 01 to 06 land. Every test gets a dated log entry (pass/fail,
who ran it, evidence file) in `docs/test_log.md`; examiners respond well to a
visible test trail.

## T1 Node soak (per node, 90 minutes, matches Battery A's design runtime)

Cold boot on battery. Checks at 0/30/60/90 min: services active, AP visible,
IBSS joined, /health updating, aux serial alive, clock_source flips to gps
after fix. Log Battery A voltage at each mark from /health; compare the
runtime against the battery decision doc's 1.74 h prediction and record the
delta (rule 9 applies if reality diverges).

## T2 Dual-radio non-disruption (the Phase 1 fix, prove it)

Phone streams continuous pings to 10.42.0.1 over the user AP while two nodes
sync repeatedly for 15 minutes. Pass: zero disassociations, ping loss under a
few percent. This single graph is the strongest before/after slide vs the
Phase 1 switcher.

## T3 DTN partition and heal

Three nodes: isolate C (power its wlan1 down), create messages on A and C,
claim on B. Reconnect C. Pass: full convergence of messages, gs_messages,
personnel, announcements, checkins within two sync cycles; audit logs show
the story; no duplicates (sqlite count checks scripted in tools/).

## T4 Auth lifecycle

Issue PIN in GCC on A -> login on B -> claim with identity -> revoke on A ->
verify B rejects after sync. Also: five wrong PINs trigger the rate limit;
token expiry forces re-login.

## T5 Aux module and fallback (bench, then field)

Pull Battery A (or kill the Pi) on node B. Pass: within 45 s node A's GCC
shows B as DEGRADED with last GPS, both battery readings, and B's last cached
message, received via LoRa (design v3 step 8 end to end). Then restore and
confirm recovery path.

## T6 BLE discovery to SOS pipeline

Emergency app armed, phone locked -> notification from a live aux module ->
join AP -> stored checkins land on the GCC map -> SOS appears in the rescue
app and gets claimed. One unbroken run, screen-recorded.

## T7 Range and channel plan sanity (field day)

- User AP usable range walk test (log RSSI vs distance, phone tool).
- IBSS sync max distance between two nodes.
- LoRa beacon reception distance at the MINIMUM power setting only, until
  the TRCSL question (master plan R1) is resolved; record TX power used in
  the log explicitly.
- With the system drone's ESP32 bridge active on its fixed channel, confirm
  DTN sync still completes (master plan R2 interference check).

## T8 Drone telemetry and relay (system drone only, props off unless Stage 2 cleared)

Bench A, direct: GCC on RESCUE_S shows heartbeat/GPS/battery/mode from the
FC through DRONE_S's mavlink-router. Bench B, mesh relay: GCC on RESCUE_A
with DRONE_S in IBSS range shows the same telemetry via 10.99.0.3. Bench C,
link-cut drill: take DRONE_S's wlan1 down mid-session; GCC command buttons
grey out within 2 seconds and the FC registers GCS loss (props off). Also
verify DB parity per file 08 acceptance 1 (DRONE_S is a first-class DTN
node). If Stage 2 was cleared per file 04's safety gates: one supervised
guided reposition inside the geofence with the RC pilot ready, video +
telemetry log archived, plus the file 08 lift test logged beforehand.

## T9 Security drills (from file 09 section 5)

Six checks, each logged with evidence like every other test: evil-twin AP
refused by the apps (and the victim portal's acceptance of it stated as the
open-plane limitation), token forgery/expiry/revocation rejected on every
node, replayed sync beacon rejected by counter, unsigned MAVLink command
ignored or firewalled (props off) while the signed GCC command works,
scripted flood throttled per-IP and globally without starving a connected
rescuer, and repo hygiene (no live secret in git history, fresh clone plus
setup script yields a working node with fresh keys).

## Examiner demo script (20 minutes, rehearse twice)

1. Cold start two nodes on batteries in front of them; narrate the boot
   (AP up, IBSS join, GPS time sync event in the log).
2. Victim path: examiner's own phone joins RESCUE_A, captive portal, sends a
   message.
3. Rescue path: PIN login live, claim on drone B, show claimed_by.
4. GCC: offline map with the pins, node health with real battery numbers,
   publish an announcement, show it arrive in the app.
5. Resilience: pull node B's Pi power; watch DEGRADED appear via LoRa with
   the last message intact.
6. Emergency app: armed phone, notification, join, SOS arrives.
7. Close with the test_log.md page and the channel/regulatory section: what
   was verified, what is estimated, what is pending TRCSL. Saying the last
   part out loud is what makes the rest credible.

## Backout criteria

If IBSS (file 01 step 5) fails T2/T3 repeatedly on the shipped kernel,
switch to the documented fallback (wlan1 AP/station cycling) and rerun T2/T3
before touching anything downstream.
