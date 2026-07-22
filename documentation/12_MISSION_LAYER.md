# 12 The Mission Layer

The mission layer (milestone M7) is what turns the working mesh, apps, and drone
control into an actual rescue operation you can plan and run end to end. It is
entirely in the GCC (plus the small backend addition for rescuer locations and
the product site in chapter 13). The operator-facing narrative and a full demo
script are in `docs/MISSION_PLANNING.md`; this chapter explains the pieces and
where they live.

## The end-to-end story

1. At HQ, online, the operator creates a mission (name, disaster type,
   challenges) and inventories resources (personnel, spare batteries, drones,
   modules).
2. Drones are added our-brand (by unit id, specs fetched from the product site),
   volunteer (a third-party drone with one of our modules attached), or minimal.
3. The operator draws the operation area on the map and places drones, or asks
   the AI advisor to propose a deployment, which they validate and approve.
4. In the field, offline, they keep planning and editing (including adding
   volunteer drones that arrive on site), deploy drones via the fleet manager
   (chapter 11), and watch the live picture.
5. Rescuers show up on the map from the location heartbeat (chapter 09).

## The mission model

`gcc_app/lib/state/mission_state.dart` (`MissionState`) is the whole operation
in one portable local JSON file. It supersedes the Phase-1-era `PlanState`
(advisory markers), and it still imports old plan files so nothing is lost.

A mission holds:

- identity: name, disaster type, challenges;
- an **area polygon** (drawn on the map);
- a **resource inventory**: personnel count, spare batteries, drones, modules;
- a **product cache**: specs fetched from the product site by unit id, so once
  fetched a unit resolves offline;
- named **deployments**, each a set of role-tagged placements
  (user_ap / mesh_relay / system_drone) with coverage radii, marked draft or
  approved, one of them active.

Drone entry supports three paths, all editable at any time including offline:
our brand (unit id), volunteer (make/model, owner, and one of our modules
attached, so comm specs resolve via the module), or minimal (label only). A
module can only be attached to one drone at a time. This is why the operation
roster is never frozen after planning: when locals arrive with a drone and we
strap a module on it, the operator adds it on the spot.

## The planner (on the map)

`gcc_app/lib/screens/map_screen.dart` planning mode:

- **Draw area**: tap polygon vertices, undo, close.
- **Placements**: drop role-colored markers with coverage circles sized from the
  cached specs; select a placement and tap a new spot to move it (flutter_map
  has no native drag).
- Save and load the whole mission as a JSON file.

## The AI deployment advisor

`gcc_app/lib/services/ai_advisor.dart`. The important thing to understand is
that **the tool is the GCC app; there is no separate AI server**. The flow:

1. The operator clicks "AI suggest" (online, at HQ).
2. The GCC builds a prompt from the mission: the area polygon, drone and module
   counts, cached spec ranges (AP range, mesh range), and challenges, plus the
   required JSON output shape.
3. It POSTs to an OpenAI-compatible chat endpoint. This is deliberately
   OpenAI-compatible so **free providers work** (Groq, OpenRouter); the endpoint,
   model, and key are entered in Settings and never committed. The default is a
   current free OpenRouter model.
4. The model returns JSON placements. The GCC parses them (tolerating code
   fences and stray prose) and **validates** them before rendering.
5. The result lands as an unapproved "AI plan" that becomes the active
   deployment; the operator edits it on the map and approves. The AI never
   commands a drone; it only proposes markers.

**The validator is the real guarantee**, because free models are not reliable.
It checks: every placement inside the polygon (point-in-polygon), count not over
available drones, at most one system drone, and mesh connectivity (each placement
within mesh range of at least one other). Failures become warnings the operator
sees; it clamps radii and defaults unknown roles rather than rejecting a
parseable-but-imperfect answer. Errors are mapped honestly: offline means "plan
manually"; 401 is a bad key; 429 is a busy free tier. Parsing and validation are
pure functions, unit-tested against canned good, fenced, malformed, and refusal
responses (`gcc_app/test/ai_advisor_test.dart`).

Online only, by design: the field plans manually.

## Rescuer location tracking

The mission layer added rescuer positions to the picture. This spans the whole
stack:

- **Backend**: a new signed, replicated table `personnel_locations`
  (latest-per-rescuer, newest-signed-`updated_at` wins), a `POST
  /personnel-location` endpoint that takes the identity from the session token
  (never the body), and `GET /personnel-locations`. It follows every existing
  security control (chapter 05) and syncs like any other record (chapter 04). The
  table is created automatically on an updated node with no migration; the
  rollout runbook is `deploy/node_update_locations.html`.
- **Rescue app**: the battery-friendly heartbeat (chapter 09).
- **GCC**: `DataStore` pulls the locations; the map shows teal person pins; Live
  Ops has a Rescuers card and a "rescuers tracked" tile.

## The live operations picture

`gcc_app/lib/screens/live_ops_screen.dart` is the single operational dashboard:
stat tiles (victims, SOS, field reports, rescuers, mesh/battery/GPS), the fleet
board (chapter 11), a rescuers card, and a known-nodes table, each figure with
its data age. The map is the spatial view of the same operation. Together they
are the honest, at-a-glance state of the whole response.

## Where the code lives

- Mission model: `gcc_app/lib/state/mission_state.dart`
- Mission tab: `gcc_app/lib/screens/mission_screen.dart`
- Planner: `gcc_app/lib/screens/map_screen.dart`
- AI advisor: `gcc_app/lib/services/ai_advisor.dart`
- Geometry: `gcc_app/lib/services/geo.dart`
- Live Ops: `gcc_app/lib/screens/live_ops_screen.dart`
- Rescuer locations (backend): `backend/models.py`, `backend/sync_engine.py`,
  `backend/api.py`; shared model in `shared_dart/lib/src/models.dart`
- Operator narrative + demo script: `docs/MISSION_PLANNING.md`
- Acceptance runbook: `deploy/mission_layer_check.html`
