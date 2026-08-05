# 12 The Mission Layer

The mission layer (milestone M7) is what turns the working mesh, apps, and drone
control into an actual rescue operation you can plan and run end to end. It is
entirely in the GCC (plus the small backend addition for rescuer locations and
the product site in chapter 13). The operator-facing narrative and a full demo
script are in `docs/MISSION_PLANNING.md`; this chapter explains the pieces and
where they live.

## The end-to-end story

1. At HQ, online, the operator creates a mission (name, disaster type,
   challenges) and **draws the operation area first**, because it frames the
   map every later step happens over.
2. They inventory resources (personnel, spare batteries, drones, modules).
   Drones are added our-brand (by unit id, specs fetched from the product
   site), volunteer (a third-party drone with one of our modules attached), or
   minimal.
3. They place the GCC itself, draw arrows for where they expect the operation
   to advance, and circle areas they suspect need attention.
4. They place drones by hand, or ask the AI advisor to propose a deployment,
   which they validate and approve.
5. In the field, offline, they keep planning and editing (including adding
   volunteer drones that arrive on site), deploy drones via the fleet manager
   (chapter 11), and watch the live picture.
6. Rescuers show up on the map from the location heartbeat (chapter 09).

The Mission tab is numbered in that order: **where**, then **what you have**,
then **the plan**. The earlier layout asked for a resource inventory before
there was anywhere to put it.

## The mission model

`gcc_app/lib/state/mission_state.dart` (`MissionState`) is the whole operation
in one portable local JSON file. It supersedes the Phase-1-era `PlanState`
(advisory markers), and it still imports old plan files so nothing is lost.

A mission holds:

- identity: name, disaster type, challenges;
- an **area polygon** (drawn on the map);
- the **operator's intent**: where the GCC is, advance arrows, and suspected
  areas (below);
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

- **Draw area**: tap polygon vertices, undo, close. Drawing it also frames the
  camera on it.
- **Place GCC**: one tap. Nothing in the system can know where the ground
  control centre is; it is a laptop in a tent with no GPS.
- **Advance arrows**: two taps, tail then head, with an optional note.
- **Suspected areas**: a tap and a radius, with a note.
- **Placements**: drop role-colored markers with coverage circles sized from the
  cached specs; select a placement and tap a new spot to move it (flutter_map
  has no native drag).
- Save and load the whole mission as a JSON file. Missions saved before intent
  drawing existed load unchanged, with the fields simply absent.

Only one drawing mode is active at a time and the panel says in words what the
next tap will do. Switching tools discards a half-finished arrow, so a dangling
start point cannot attach itself to an unrelated tap later.

### Why intent is a first-class part of the mission

The map says where the disaster is, and that is all it says. Which way the
teams are moving through it, and which corners the operator is worried about,
exist nowhere else in the system and cannot be inferred from a polygon. Before
this the advisor was being asked to plan without the one input only a human
has.

Resources are cards and chips rather than lists: a drone card is a drop target,
and a SPARE module chip drags onto it to attach. A module already fitted is not
draggable, which matches both the physical act and the rule that a module
cannot be on two airframes. The dropdown in the add dialog remains, because
drag-and-drop with a trackpad in a hurry is not something anyone should be
forced into.

## The AI deployment advisor

`gcc_app/lib/services/ai_advisor.dart`. The important thing to understand is
that **the tool is the GCC app; there is no separate AI server**. The flow:

1. The operator clicks "AI suggest" (online, at HQ).
2. The GCC builds a prompt from the mission: the area polygon, drone and module
   counts, cached spec ranges (AP range, mesh range), challenges, and the
   operator's intent, plus the required JSON output shape. The intent is
   labelled for what it is: arrows are stated as something the model cannot
   infer, and suspected areas are explicitly flagged as hunches to be weighted
   BELOW the area polygon rather than treated as confirmed reports.
3. It POSTs to an OpenAI-compatible chat endpoint. This is deliberately
   OpenAI-compatible so **free providers work** (Groq, OpenRouter); the endpoint,
   model, and key are entered in Settings and never committed. The default is a
   current free OpenRouter model.
4. The model returns JSON placements. The GCC parses them (tolerating code
   fences and stray prose) and **validates** them before rendering.
5. The result lands as an unapproved "AI plan" that becomes the active
   deployment; the operator edits it on the map and approves. The AI never
   commands a drone; it only proposes markers.

**An unapproved plan is visible only in planning mode**, where it blinks, and
never on the operations map. This is a safety property rather than a
presentation choice: a proposal drawn on the same map as the live operation is
indistinguishable from a decision, and this proposal came from a model that has
never seen the ground. Withdrawing approval hides it again, which has its own
test (`gcc_app/test/draft_visibility_test.dart`).

### What the progress display honestly shows

While the advisor runs, the GCC shows four steps: reading the mission, asking
the model, checking the plan, placing on the map. The first three are real
work, and asking is the long network wait.

**Placing on the map is a reveal, not streaming.** The model returns every
placement at once; showing them appear one at a time lets the operator watch
where each lands instead of a plan materialising whole, and the step is worded
as placing rather than as receiving. Nothing in the UI claims the model is
thinking step by step, because it is not.

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

## What victims are shown, per mission

`backend/mission_config.py` holds the option list a node serves victims, and
the GCC pushes it per node. Three properties matter more than the feature
itself:

- **Stock options always work.** A node nobody pushed to serves a built-in
  need-based list ("I am trapped", "I need water") rather than nothing. It is
  never wrong, only less tailored, and an unconfigured node is the normal state
  early in a rollout.
- **Every node reports which config it holds**, so the GCC can show per node
  whether it matches what the operator has loaded. Silent partial rollout is
  the failure mode that bites: pushing happens once per drone, because the
  operator has to join each in turn.
- **There is no version counter.** A counter has to be stored somewhere and
  kept correct, and whoever holds it can be wrong: a fresh GCC install, a
  second operator's laptop, or cleared settings all rewind it, and the operator
  then gets pushes rejected with no visible cause. A config instead identifies
  itself by a hash of its own content, so pushing identical options twice is
  correctly reported as "already matches" rather than inventing a difference.

The option list may be edited **once per mission** and then pushed. That is the
operator's decision, recorded because it overrides a suggestion that a mission
changing character justifies a second edit: keeping several revisions in play
makes "which options is this node actually serving" hard to reason about, and
that ambiguity is worse than the flexibility. It locks EDITING, not pushing.

### Missions scope credentials

Each config carries a `mission_id`, and personnel records are issued against
it. A node running a different mission rejects those credentials at login, so
activating a new mission retires every credential from the old one at a stroke.
An empty mission id means "no active mission" and accepts any credential, which
is the state before the operator has pushed anything; locking people out of an
unconfigured node would be worse than useless.

Because pushing a different mission id signs rescuers out, the GCC's push
dialog turns red and says so explicitly. It must never be a quiet side effect
of a button labelled "push options". Chapter 05 covers what mission scoping is
holding up on the security side.

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
