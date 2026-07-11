# HOW TO USE THESE FILES (instructions for Claude Code)

Read 00_MASTER_PLAN.md fully before writing any code. Then implement the
work packages in order: 01 -> 02 -> 03 -> 04 -> 08 -> 05 -> 06 -> 07.
File 03 may run in parallel with 01/02. File 08's Pi setup happens together
with 01 (same image, drone_s.conf); its MAVLink relay part comes after 04
Stage 1, and 05/06 can proceed in parallel with it. File 09 (security
architecture) is cross-cutting: read it together with 00 and apply its
tasks inside 01/02/04/05/08 as mapped in its section 4. Do not start a
package before its dependency's acceptance list passes.

Ground rules that apply to every package (these mirror the project's thesis
rules and must not be violated):

1. This is an examined final-year thesis. Every technical value (current,
   voltage, timing, range) used in code comments or docs needs a stated
   source and a confidence label: High (manufacturer datasheet/official
   doc), Moderate (official FAQ or corroborated measurement), Low (single
   community estimate). If no source exists, say so and mark it an estimate
   to be verified by measurement.
2. Never invent part numbers or specs. Describe generically if unverified.
3. Every design choice gets: what was chosen, why, the realistic
   alternatives, and why each was rejected. The master plan models this
   format; follow it in code-adjacent docs and commit messages for
   significant decisions.
4. Show calculation steps for any numeric result, never just the answer.
5. If an implementation finding changes a figure or decision recorded in an
   earlier project document (design v3, battery decision doc), flag it
   explicitly in the PR/commit and in docs/CHANGES.md; never silently drift.
6. Scope guard: the two volunteer drones receive communication modules only.
   No flight controller, ESC, motor, or airframe work for them. Flight
   integration code targets the single system-owned drone and is gated on
   file 04 Stage 0. The third Pi flies on the system-owned drone as node
   DRONE_S (file 08): full node software plus the MAVLink gateway, no aux
   module by default.
7. Configuration over constants: node identity, SSIDs, IPs, ports,
   intervals live in /etc/rescue-mesh/node.env or app settings, not code.
8. Do not weaken security controls on your own initiative. The security
   posture changes ONLY as specified in file 09, which records what is
   kept, fixed, and demoted, with reasons. Anything not listed there stays
   as Phase 1 built it (role keys, HMAC signatures, audit logging, rate
   limits).
9. Do not use the em dash character anywhere in generated text, comments,
   or documents. Use hyphens, commas, or colons.
10. Formal documents for the supervisor (e.g. design v4, updated progress
    report) are produced as .docx with plain formatting: black text, Times
    New Roman 12, simple bordered tables, no shading. The .md files here are
    engineering instructions, not that deliverable.

Repository layout targets:
- backend/            existing FastAPI code (rpi_ files), modified per 02
- backend/archived/   retired switcher.py and ble_discovery.py with a note
- deploy/             node setup script, unit files, configs, VERIFY.md (01)
- firmware/aux/       ESP32-C3 unified firmware + TESTS.md (03)
- gcc_app/            Flutter Windows Ground Control Center (04)
- rescue_app/         existing Flutter app, updated (05)
- emergency_app/      new public Flutter app (06)
- shared_dart/        shared models + API client package (04/05/06)
- tools/              aux_sim.py, sync verification scripts (02/03/07)
- docs/               test_log.md, CHANGES.md, DRONE_LINK.md
