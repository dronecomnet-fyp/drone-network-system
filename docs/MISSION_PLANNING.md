# MISSION_PLANNING: the end-to-end rescue operation (M7)

Status: implemented 2026-07-21. This is the whole operation story, HQ to
field, that ties together the GCC app, the product site, the mesh nodes, and
the drones. Nothing here changes the flight policy: drones are commanded
props-off on the bench only (see CHANGES item 23).

## The flow, in order

1. HQ, online. The operator opens the GCC and creates a mission on the
   Mission tab: name (e.g. "Flood 2026"), disaster type, and challenges.

2. Inventory. The operator lists resources: personnel count, spare
   batteries, comm modules (by our unit ID), and drones. Drones come three
   ways, and the roster is editable at ANY time, including offline in the
   field:
   - OUR BRAND: enter the unit ID, tap "fetch specs" (pulls from the product
     site and caches into the mission).
   - VOLUNTEER: a third-party drone (make/model + pilot name) with one of our
     modules attached; the module's unit ID resolves the comm coverage specs.
   - MINIMAL: just a label, specs unknown.
   A module can only be attached to one drone at a time.

3. Product specs. The GCC fetches a unit's specs from the hosted product
   site (Supabase) by ID and caches them into the mission file, so once
   cached they resolve with no network. The public site (website/) shows the
   catalogue, a 3D product view, a unit lookup, and a request-a-quote form.

4. Plan the area. On the Map tab, planning mode, the operator draws the
   operation area polygon and drops placements (role-colored: user AP, mesh
   relay, system drone) with coverage circles sized from the cached specs.

5. AI suggestion (optional, online). "AI suggest" on the Mission tab sends
   the mission (area, counts, specs, challenges) to a free OpenAI-compatible
   model, which returns placements. The GCC validates them (inside the area,
   count vs drones, mesh connectivity, one system drone) and drops them in as
   an unapproved "AI plan" the operator edits and approves. The AI never
   commands anything.

6. Field, offline. At the disaster the operator plans or edits manually (no
   internet needed), including adding volunteer drones that arrive on site.
   Deployments and the whole mission save/load as a local JSON file.

7. Deploy. On Live Ops, the fleet board deploys drones to placements. In
   DEMO mode any number of drones are simulated: they fly out, hold station,
   and auto-return before the battery reserve is spent; volunteer rows are
   pilot-advisory (the GCC shows the pilot instruction). For DRONE_S with a
   live MAVLink link, "command over MAVLink" does the real arm/takeoff/goto
   sequence, props-off, with a battery watchdog that issues return-to-launch.
   The board shows "Deployed X / Y available" and disables Deploy when the
   pool is empty.

8. Live operations. Live Ops shows the numbers (victims, SOS, field reports,
   rescuers tracked, mesh/battery/GPS), each with its data age. The Map shows
   everyone's last known location: victims, SOS check-ins, rescuers (teal
   pins, from the location heartbeat), the connected node, degraded nodes,
   and the deployed drones moving through their lifecycle.

## The no-fly demo script (about 15 minutes)

Setup: two mesh nodes powered (A + B), DRONE_S on the bench with props OFF
and the flight battery connected, the GCC laptop, one phone with the rescue
app, one with the emergency app. Product site open in a browser (online) for
the HQ portion.

1. HQ, online (2 min). Create "Flood 2026" on the Mission tab. Add DRONE_S by
   unit ID DRN-S-0007 and tap fetch specs (pulls from the product site).
   Add a volunteer "DJI Mavic" with module DCM-A-0042 attached. Show the
   product site: catalogue, 3D view, unit lookup for DRN-S-0007.

2. Plan (3 min). On the Map, draw the area polygon over the demo location.
   Tap "AI suggest": show the returned placements land as a draft with any
   warnings, then edit one on the map and tick approve.

3. Go offline (1 min). Disconnect HQ internet. Show that planning still
   works: add another placement manually, save the mission to a file, load it
   back. This is the field phase.

4. Rescuers on the map (2 min). Log in on the rescue app; leave it open. In
   about 90 s the rescuer appears on Live Ops (Rescuers card) and as a teal
   pin on the Map. Toggle "Share my location" off and on in the app to show
   the control. On the emergency app, send an SOS and show it appear as an
   orange check-in.

5. Fleet, DEMO (3 min). On Live Ops, deploy the volunteer drone (DEMO): watch
   it fly to station, hold, and auto-return as its modelled battery hits the
   reserve. Deploy until the pool is empty to show "No more drones
   available". Use "simulate signal loss" on one to show it drop to FALLBACK
   (the LoRa story) then LOST.

6. Fleet, REAL, props-off (3 min). Connect the GCC to DRONE_S's MAVLink
   (Drone tab, link fresh). Deploy DRONE_S with "command over MAVLink":
   narrate that this is the real arm/takeoff/reposition command sequence,
   observed on the bench with props off. Show the motors spin on a motor
   test, show force-DISARM always available, and show the battery watchdog
   would issue return-to-launch below the per-cell threshold. State plainly:
   we do not fly, by choice, for safety.

7. Wrap (1 min). Live Ops as the single operational picture: victims, SOS,
   rescuers, mesh health, and the fleet board, each figure honest about its
   age. Planned vs actual: the deployed drone markers vs where DRONE_S
   actually is (its bench GPS).

## What examiners should take away

- One platform runs the whole operation even though only one drone is ours:
  the inventory, planning, AI suggestion, live tracking, and fleet
  coordination are all real; multi-drone flight is simulated honestly and
  labelled as such.
- Every position on the map carries its data age; nothing pretends to be more
  live than the DTN mesh allows.
- Security is unchanged and additive: the new rescuer-location table is
  signed and verified like every other synced record, identity comes from the
  session token, and no secret (Supabase service_role key, AI key) is
  committed.

## Setup the operator provides (once)

- Supabase project for the product site: apply website/supabase/schema.sql,
  then enter the URL + anon key in the site's .env and in GCC Settings.
- A free LLM key (Groq or OpenRouter) in GCC Settings for the AI advisor.
- The node software update for rescuer locations: deploy/node_update_locations.html.
- Offline map (.mbtiles) for the region, loaded in GCC Settings (docs/OFFLINE_MAPS.md).
