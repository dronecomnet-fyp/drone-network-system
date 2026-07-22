# 18 Handover and Future Work

This chapter is for the next team. It tells you what is done, what is not, and
where to start. Read chapters 02 and 03 first for the shape and the intent; this
chapter assumes them.

## What is done

All the software that can be built and tested without the physical fleet is
done and verified:

- The node backend (both planes, schema v3, DTN sync, aux bridge, crypto),
  passing 28 pytest tests.
- The deploy tooling: one setup script, per-node configs, systemd units, the
  fleet CA, the firewall, and the browsable runbooks.
- The aux firmware (compiles clean; six bench tests documented).
- The three apps (GCC 41 tests and analyze-clean; rescue and emergency apps
  analyze-clean).
- The system drone control: the MAVLink gateway, the GCC MAVLink service, and
  the fleet manager (demo and real), all bench-verified props-off.
- The mission layer: mission planning, the AI advisor, rescuer tracking, live
  operations.
- The product website, live on GitHub Pages with a seeded Supabase backend.

## What is not done, and why

Most open items are **hardware-gated**: they need the physical drones, radios,
and flight controller assembled and on the bench. They are not blocked by
software.

- **Fleet bring-up on real hardware.** The node setup, the two-node mesh, the
  DRONE_S bring-up, and the aux flashing have runbooks (`deploy/*.html`,
  `firmware/aux1/windows_bringup.html`) but must be executed on the physical
  cards and verified against `deploy/VERIFY.md` and `firmware/aux1/TESTS.md`.
- **Python deps re-verified on the Pi.** The Bookworm / Python 3.11 environment
  should be confirmed against the pinned `requirements.txt` (VERIFY.md step 0).
- **Integration tests on the assembled fleet (file 07, T1-T9).** The security
  drills and the end-to-end operation checks run on the real fleet; the
  automated equivalents pass, but the on-fleet acceptance is pending.
- **The GCC Windows release build.** Development runs on macOS; the installable
  Windows build follows `docs/RELEASES.md` and must be produced on a Windows
  machine.

## Deliberate scope boundaries (do not treat these as bugs)

- **The drones are not flown.** Flight commands are bench-verified props-off.
  Free flight waits for a deliberate safety and airworthiness setup, an RC
  transmitter, and flight controller tuning. Keep this policy until you change it
  on purpose (chapter 11).
- **Rescuer tracking is foreground-only.** Battery tradeoff; last-known position
  with age, not a live stream (chapter 12).
- **AI planning is online-only** (HQ phase); the field plans manually.
- **The product website's cart is request-a-quote**, not real orders.

## The residual risks that are named on purpose

These are recorded, accepted, and have a stated response; they are future
hardening, not oversights:

- **Physical capture** of a node exposes the shared master secret. Response: the
  key-rotation runbook (`SECRETS_ROTATION.md`). A per-node Ed25519 identity would
  remove the shared-secret exposure and is the natural next security step.
- **MAVLink 2 packet signing** (file 09 plane 4 layer 2) is not implemented; the
  control link is protected by network isolation (layer 1) instead. Implementing
  SETUP_SIGNING between the GCC and the flight controller closes this.
- **Victim plane is plaintext** by design (chapter 05). This is the accepted
  tradeoff, not a gap.

## A roadmap for the next team

Roughly in order of value:

1. **Finish the on-hardware bring-up and the T1-T9 integration acceptance.** This
   is the highest-value work: it turns "verified in software" into "verified on
   the fleet". Everything you need is in the runbooks.
2. **Per-node Ed25519 identities.** Removes the shared-secret single point of
   compromise (the biggest security improvement available).
3. **MAVLink 2 signing** between the GCC and the flight controller.
4. **Background rescuer tracking** as an opt-in foreground service (the
   emergency app's `location_logger.dart` is the pattern to copy), if the field
   wants continuous positions.
5. **Real multi-drone flight**, only after a safety plan: more flight
   controllers, RC transmitters, tuning, and a flight-test protocol. The fleet
   manager's REAL path already generalises beyond one drone in software.
6. **A second mesh hop / larger fleet.** The DTN design is three nodes today;
   test it at more nodes and larger areas, and revisit whether 802.11s becomes
   worth it (it was rejected for three nodes, chapter 16).
7. **Product hardening of the apps** (offline map management, app store
   packaging, accessibility).

## How to onboard as a new team member

1. Read chapters 01, 02, 03 for the what, the shape, and the why.
2. Run the software you will work on locally following chapter 15 (backend
   pytest, `flutter run` for an app). Everything runs without hardware except
   the on-fleet steps.
3. Read the chapter for your component, then open the files it points to.
4. When you change something that alters a recorded figure or decision, add an
   entry to `docs/CHANGES.md` (chosen / why / alternatives), and update the
   relevant handbook chapter. Keep the paper trail honest; it is part of the
   deliverable.
5. Keep the writing conventions: no em dash characters; sourced figures with
   confidence labels; decisions recorded with alternatives.

## The two rules that will save you the most time

- **Never run `make_fleet_ca.sh` on any node except DRONE_A.** Copy A's
  `deploy/secrets/` to the others. A mismatched key set makes nodes silently
  reject each other and is the most confusing failure to debug (chapters 05, 14).
- **401 means re-login, 403 means wrong role.** Do not log a user out on a 403.
  This distinction is load-bearing across the apps (chapter 05).

## Who to ask

This handbook, `docs/CHANGES.md`, and the `Instructions_MD_files/` specs are the
written memory of the project. Between them they record not just what the system
does but why it does it that way. When something is unclear, the answer is
usually in the decision record; when it is not, the code is the final authority,
and please write down what you learned so the team after you does not have to
ask again.
