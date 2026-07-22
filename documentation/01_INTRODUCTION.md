# 01 Introduction

## The problem

When a flood, earthquake, or landslide hits, the first thing to fail is
communication. Cell towers lose power or backhaul, and suddenly the people
who most need to reach help cannot, and the rescue teams who are there cannot
coordinate or even find each other. Satellite phones are scarce and expensive.
The gap between "disaster happens" and "an organised response with a working
network" can be hours or days, and that gap costs lives.

## The idea

Put a small communication module on a drone. Each module is a Raspberry Pi
with two radios:

- a **5 GHz access point** that phones connect to, exactly like normal Wi-Fi,
  so a victim needs no special app to send a plea for help; and
- a **2.4 GHz ad-hoc radio** that links the drones to each other, forming a
  network that carries messages between them and back to a ground control
  centre.

Fly a few of these over the affected area and you have rebuilt a local network
in minutes. A victim connects to the nearest drone and submits their location
and situation through a captive portal. That message hops across the drones
(store-and-forward, so it gets there even when the drones are not all in range
at once) to the rescue teams and the ground control centre.

Because the drones may drift in and out of range of each other, this is a
**delay-tolerant network (DTN)**: nodes sync whenever they meet, and no single
always-on link is assumed. That property is the heart of the design.

## The system in one paragraph

Three drone-mounted Pi **nodes** form a DTN mesh. Victims and rescuers connect
to a node's Wi-Fi. Victims send messages and SOS check-ins; rescuers log in,
claim messages, and file field reports; all of it syncs fleet-wide. A **ground
control centre (GCC)** desktop app gives the operator the whole picture: a map,
live numbers, personnel management, and mission planning. One drone (**the
system drone**, DRONE_S) additionally carries a flight controller the GCC can
command over MAVLink. A small **aux module** (an ESP32-C3) on each drone adds
battery/GPS sensing and a LoRa fallback beacon so a drone stays locatable even
if its Pi dies. A public **product website** presents the hardware and lets the
GCC look up a unit's specs by its ID.

## The two project phases

This is a two-phase final-year project.

**Phase 1** proved the concept and worked, but with documented limitations
(see chapter 03 for the full list):

- A single radio time-sliced between being an access point and syncing, so
  users dropped off the Wi-Fi during every sync cycle.
- Bluetooth discovery never actually worked (it used classic inquiry, not BLE
  advertising).
- Field reports never synced between nodes.
- There was no personnel authentication, no desktop operator app, and no
  public victim app.
- Security was one shared secret and self-signed certificates that the apps
  accepted blindly.

**Phase 2** (this codebase) rebuilt the system to remove those limitations,
adding a second radio for an always-on mesh, real BLE, fleet-wide sync of
everything, per-purpose cryptographic keys with real certificate pinning, a
personnel login system, three polished apps, drone flight control, and a full
mission-planning and live-operations layer.

Phase 1 lives on in the repository as evidence: `local-server/` and
`rescue-personnel-app/` (and `previous_codes/`) are the original Phase 1 code,
kept untouched and git-ignored from the build. Phase 2 code was copied in and
rebuilt, never edited in place, so the paper trail stays honest.

## How the work was organised

Phase 2 was specified as eleven authoritative documents in
`Instructions_MD_files/`:

- `00_MASTER_PLAN.md`: the overall plan and the key design decisions.
- `01`-`08`: one work package each (Pi rebuild, backend, firmware, GCC app,
  rescue app, emergency app, integration tests, system drone).
- `09_SECURITY_ARCHITECTURE.md`: the cross-cutting security design, applied
  inside packages 01, 02, 04, 05, and 08.
- `README_FOR_CLAUDE_CODE.md`: the ground rules (config over constants,
  sourced figures, decisions recorded with alternatives, no em dashes,
  security changes only as specified in file 09).

Implementation proceeded as milestones M1 through M7. M1-M3 built the
foundation (backend, deploy, firmware, apps, drone control); M7 added the
mission layer (planning, live ops, AI advisor, product site, rescuer tracking).
Chapter 16 records the decisions; chapter 18 lists what remains.

## The team and the handover

This project is built and maintained by a student team, and it is designed to
be handed to the next group of students who continue it. That is why this
handbook exists: everything that was implemented, planned, designed, and
decided is written down, with the reasoning, so the next team does not have to
reverse-engineer intent from code.

If you are that next team: start at chapter 02 for the shape of the whole
system, read chapter 03 to understand why it looks the way it does, then dive
into whichever component you will work on. Chapter 18 tells you what is not yet
done and where to begin.

## What this project is not

- It is not a replacement for professional emergency communications; it is a
  rapidly-deployable stopgap that rebuilds a local network where none exists.
- In this phase the drones are **not flown**. The system drone's flight
  commands are verified on the bench with propellers removed. Actual flight is
  deliberately out of scope until a proper safety and airworthiness setup is
  done (chapter 11). This is a safety choice, not a capability gap: the command
  pipeline works and is demonstrated props-off.
