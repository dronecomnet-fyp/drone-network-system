# 16 Design Decisions

Every significant decision in this project was recorded with what was chosen,
why, and what was rejected. This chapter curates the important ones so the next
team understands the intent, not just the result. The full and authoritative
records are:

- `Instructions_MD_files/00_MASTER_PLAN.md` decisions D1-D6 (the Phase 2 plan);
- `docs/CHANGES.md` (every change to an earlier figure, numbered 1-25);
- `Instructions_MD_files/09_SECURITY_ARCHITECTURE.md` (the keep/fix/demote
  security decisions).

## The foundational decisions (master plan)

**D1: A clean rebuild, not an in-place upgrade.** Chosen because Phase 1 cards
carried single-radio switcher state, stale profiles, and undocumented drift, and
a scripted rebuild from a blank card gives reproducibility. Rejected: in-place
upgrade (high risk of hidden state, impossible to document honestly) and keeping
one node old for comparison (mixed fleets are sync-incompatible). Consequence:
the schema changes to v3 with no migration from Phase 1. See chapter 03.

**D2: The DTN backbone is IBSS with static IPs, not AP/client role cycling.**
The central decision. Chosen for no role switching, any pair syncing at any
time, the simplest sync loop, and the AR9271's IBSS support. Rejected: the
Phase 1 style of cycling (reintroduces timing fragility; kept as a documented
fallback) and 802.11s + BATMAN-adv (overkill for three nodes, weakens the DTN
narrative). This is the chapter 03 / chapter 04 story.

**D3: BLE moves entirely to the ESP32; the Pi's Bluetooth is disabled.** Chosen
to remove the Pi Wi-Fi/Bluetooth coexistence problem and because the old Pi
approach was never real BLE. See chapter 07.

**D5 and file 08: DRONE_S and drone control.** The system drone's evolution from
"single radio, direct control only" to "second AR9271, full mesh node, MAVLink
gateway" is the biggest mid-project reversal, recorded in `docs/CHANGES.md`
items 11-19. See chapter 11.

## The security decisions (file 09)

Sorted keep / fix / demote (chapter 05 has the detail):

- **Fixed F2:** one shared secret became three HKDF-derived purpose keys.
- **Fixed F3:** the victim flow moved to plain HTTP (a certificate warning is a
  usability cost with no authentication value to a victim; integrity is
  protected by signing at ingest).
- **Fixed F4:** no secrets in git, ever; rotate anything previously committed.
- **Fixed F6:** beacon replay closed with a per-node monotonic counter
  (counter, not clock, because a node may run on relative time).
- **Fixed (plane 2):** a fleet CA with per-node certs and real app-side pinning,
  replacing accept-any-certificate.
- **Demoted (D1):** inter-node mutual TLS, off by default (per-record HMAC
  covers the need in a three-node fleet).
- **Demoted (D2):** fleet-keypair end-to-end victim encryption, off by default
  (a private key on every rescuer phone is a shared secret in asymmetric
  clothing, and a mismanaged key mid-disaster makes pleas unreadable).

## The mission-layer decisions (M7, CHANGES 20-25)

- **New table `personnel_locations` (20):** latest-per-rescuer, newest-signed
  wins, not append-only, because the GCC needs one current marker per rescuer,
  not a history. Identity comes from the session token, never the body.
- **Foreground-only rescuer tracking (21):** an accepted limitation for battery;
  the operator sees the last-known position with its age, not a live stream.
  Continuous background tracking is documented future work.
- **Product data on a real hosted backend (22):** Supabase with row-level
  security; the anon key is public by design and RLS is the access control; the
  service_role key is never committed.
- **A two-mode fleet manager, not multi-drone flight (23):** DEMO simulation for
  any count plus a real path for DRONE_S only, because only DRONE_S has a flight
  controller we command. Flight policy unchanged: props-off bench only.
- **An OpenAI-compatible AI advisor, not the Anthropic API (24):** because a free
  tier was required; the model only proposes JSON, the app validates it, the
  operator approves. Online-only; the field plans manually.
- **`MissionState` supersedes `PlanState` (25):** the whole operation in one
  local JSON file, with legacy plan import so nothing is lost.

## The recurring principles behind the decisions

Reading the decisions, a few principles recur and are worth internalising:

- **Honesty over illusion.** Every screen shows data age; nothing pretends to be
  more live than a DTN allows. The fleet manager simulates the drones we cannot
  fly and labels them DEMO. This honesty is a feature, especially for an examined
  project.
- **Proportionate security per plane.** Open where openness is necessary (the
  victim plane), strong where the stakes are high (drone control, inter-node),
  and residual risks are named rather than hidden.
- **Config over constants, and reproducibility.** One setup script, per-node
  config, no hard-coded identities, a clean rebuild from a blank card.
- **Build the needed thing, document the alternative.** The IBSS fallback and
  the demoted crypto capabilities are documented but not built preemptively.
- **Record why, with rejected alternatives.** So a future reader (you) does not
  re-litigate a settled decision or repeat a rejected path.
