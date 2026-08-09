# Chapter 4 restructure: 4.1 Volunteer module, 4.2 System drone

Report-ready content. Paste and adjust wording to match your voice.
Everything factual here was checked against the code; anything I could
not verify is marked **VERIFY** with what to check.

Chapter 4 currently describes one thing, the communication module, as
though it were the only hardware. It becomes two:

| Section | Covers | Applies to |
|---------|--------|-----------|
| 4.1 | Volunteer communication module | DRONE_A, DRONE_B |
| 4.2 | System drone | DRONE_S |

**4.1 needs no rewriting.** Retitle it "Volunteer Communication Module",
move the existing 4.1 to 4.2 subsections, and add a sentence at the top
saying the module is designed to be carried by an aircraft the project
does not own or modify. That single sentence is what makes the Zero
Access claim in your abstract concrete.

---

# 4.2 System Drone

## 4.2.1 Why the fleet includes a drone the project owns

The volunteer model in 4.1 deliberately asks nothing of the host
aircraft. That is its strength and also its limit: a volunteer drone
carries the network but the project cannot command it, so it cannot
demonstrate coordinated placement, station keeping, or automated return.

DRONE_S exists to close that gap. It runs the same node software as the
volunteer nodes, so it is a full participant in the mesh, and in addition
it exposes its flight controller to the Ground Control Center. It is
therefore the only aircraft in the fleet that the system can both talk
THROUGH and talk TO.

The distinction is worth stating plainly because it bounds every claim in
Chapter 6: the fleet management logic is demonstrated across any number
of drones in simulation, and commanded for real on exactly one.

## 4.2.2 Airframe and propulsion

The aircraft is a pre-built carbon fibre quadcopter adopted rather than
designed. Adopting it was a deliberate scope decision: the project's
contribution is the communication payload, and building an airframe would
have consumed time without advancing that contribution.

| Component | Specification | Notes |
|-----------|---------------|-------|
| Frame | Carbon fibre, X configuration, 210 to 250 mm class | **VERIFY** the exact diagonal, it sets the prop clearance |
| Motors | 4x EMAX RS2205, 2300 KV brushless | A widely used 5 inch class motor |
| ESCs | 4x 40 A brushless, 2 to 4S | Each with a 5 V / 3 A BEC |
| Propellers | Gemfan Hurricane 51499, 3 blade, 5.1 in diameter, 4.99 in pitch | Supplied 2L / 2R |
| Battery | 3S or 4S LiPo | Set by the ESC rating |
| Power connector | XT60 male, 14 AWG silicone | |

The 2300 KV motor and 5.1 inch three blade propeller combination is a
high thrust, short endurance configuration typical of agile 5 inch
quadcopters. **That matters for this project and should be said**: the
airframe was chosen for availability, not for loiter time, and it is not
optimised for the long station keeping that a communication relay
ideally wants. Endurance figures for the aircraft therefore should not be
generalised into claims about the network's endurance, which is governed
by the module's own battery in 4.1.

## 4.2.3 Flight control and navigation

| Component | Specification | Role |
|-----------|---------------|------|
| Flight controller | OpenPilot CC3D Revolution Mini | Stabilisation and flight dynamics |
| GPS | Ceramic patch antenna module, u-blox NEO-M8N class | Position hold, return to launch. **VERIFY** the exact part |
| Companion computer | Raspberry Pi 4 Model B | Node software plus the MAVLink gateway |

> **VERIFY, and it matters more than the others.** The Ground Control
> Center speaks MAVLink. The CC3D Revolution's original OpenPilot and
> LibrePilot firmware uses UAVTalk, not MAVLink, so the board must be
> running firmware that speaks MAVLink for the control path to work at
> all: an iNav or ArduPilot target for the Revo Mini. Confirm which
> firmware and version is actually flashed and state it in this table.
> An examiner familiar with this board will ask, because the pairing of
> "CC3D" and "MAVLink" is not obvious.

The donor build also carried an ESP32 development board acting as a
wireless bridge. It is not used in this configuration: the Raspberry Pi
is the companion computer, connected directly to the flight controller,
which removes a hop and means no flight controller reflash is required
for telemetry to reach the ground station.

## 4.2.4 One aircraft, two independent roles

DRONE_S runs the identical node software described in Chapter 5, so from
the mesh's point of view it is an ordinary peer: it serves a user access
point, holds a replica of every synchronised table, and participates in
sync exactly as DRONE_A and DRONE_B do. Adding flight control did not
fork the node software.

The second role is added by one extra service, the MAVLink gateway,
which does two separate jobs:

**A transparent control bridge.** Raw MAVLink bytes are forwarded
unmodified in both directions between the flight controller's serial link
and a UDP endpoint on port 14550. Forwarding bytes rather than parsing
and re-emitting them means a command cannot be corrupted in transit by
the gateway itself.

**A read-only telemetry tap.** The gateway parses a COPY of the
controller-to-ground stream and harvests three messages into the node's
own health record:

| MAVLink message | Used for |
|-----------------|----------|
| `GPS_RAW_INT` | Position, fix quality and satellite count |
| `SYS_STATUS` | Flight battery voltage |
| `SYSTEM_TIME` | Setting the Pi clock from GPS time |

That third row resolves something specific to this node. DRONE_S has no
auxiliary module, so it has no INA3221, no LoRa radio and no independent
GPS. Without the tap it would have no position and no trusted clock, and
would be stuck on relative timestamps. Taking them from the flight
controller means the aircraft's own navigation sensors serve the
communication node as well, which is a genuine benefit of putting the
companion computer directly on the flight controller.

**Consequences of having no auxiliary module**, which belong in the
report because they are real limitations rather than oversights:

- No LoRa fallback beacon. If this Pi fails, the node goes silent
  entirely. The volunteer nodes can still report themselves after a Pi
  failure; DRONE_S cannot.
- No independent battery monitoring. The reported voltage is the flight
  battery, seen through the flight controller.
- No BLE advertisement, so the emergency application cannot discover this
  drone passively. Victims can still join its access point directly.

## 4.2.5 Two power domains

This is worth its own subsection because the two batteries in 4.1 are not
the same as the two power sources here.

| Domain | Source | Feeds |
|--------|--------|-------|
| Flight | 3S or 4S LiPo via XT60 | Motors, ESCs, flight controller |
| Node | **VERIFY** | Raspberry Pi 4 and the USB WiFi adapter |

The node domain needs a decision recorded explicitly, and the project has
already measured why it matters. Field testing established that a
Raspberry Pi 4 plus the AR9271 adapter cannot be reliably powered by a
supply that cannot sustain roughly 3 A: the adapter browns out and drops
off the USB bus, and the failure is silent from the application's point
of view (Chapter 6).

The ESCs provide a 5 V / 3 A BEC. That is at the very edge of the
measured requirement, not comfortably above it. Two options, and the
report should say which was chosen and why:

1. **Separate node battery**, as on the volunteer nodes. Keeps the node
   alive independently of flight power and keeps the measured 3 A
   requirement away from the BEC, at the cost of weight.
2. **Powered from the flight battery via BEC.** Simpler and lighter, but
   couples node uptime to flight battery state and runs the BEC near its
   limit with a load already proven to be marginal.

**VERIFY which is fitted.** If it is option 2, state the brownout risk
explicitly rather than leaving it implicit, because the measurement
already exists and an examiner reading Chapter 6 will connect them.

## 4.2.6 Interface summary

| Interface | Connects | Purpose |
|-----------|----------|---------|
| USB serial, `/dev/ttyACM0` | Pi to flight controller | MAVLink, both directions |
| UDP 14550 | Gateway to Ground Control Center | Control and telemetry endpoint |
| Onboard WiFi | Pi | 5 GHz user access point, RESCUE_S |
| USB 3.0 | Pi to AR9271 adapter | 2.4 GHz mesh backbone, 10.99.0.3 |
| microSD | Pi | Operating system, database, logs |

Note the flight controller link is USB CDC, so the configured baud rate
is nominal and ignored by the transport. If the build is later changed to
a hardware UART on the Pi's GPIO header, the baud rate becomes real and
must match the flight controller's telemetry port setting.

## 4.2.7 Safety policy

State this in the hardware chapter as well as the testing chapter,
because it bounds what the hardware was ever allowed to do.

All flight commands are verified **with propellers removed**. Commands
are observed to reach the flight controller, motors are confirmed to
respond during a motor test, and the battery watchdog is confirmed to
fire, all on the bench. Free flight is out of scope and awaits a
deliberate airworthiness and safety setup.

This is a scope boundary, not an unimplemented feature. The command path
is complete and tested; the decision not to fly is separate and
deliberate.

---

# 5.x Ground Control Center: drone control interface

Place this in Chapter 5 with the other Ground Control Center screens, not
in Chapter 4. **Note the current draft says this tab is "a preparation
interface rather than an active control interface", which is out of
date.** It is implemented.

## Connection model

The operator connects to the gateway over UDP, and the interface makes
the two possible paths explicit because they have different reliability:

| Path | When | Route |
|------|------|-------|
| Direct | Laptop joined to RESCUE_S | `10.42.0.1:14550` |
| Relay | Laptop joined to RESCUE_A or RESCUE_B | Volunteer node forwards over the mesh to `10.99.0.3:14550` |

Both are LIVE paths. Flight commands are never stored and forwarded, and
this is a deliberate rule rather than an implementation limit: a command
that arrives late is worse than one that never arrives, because the
operator has moved on and the aircraft has not.

## Heartbeat gating

Every command is gated on a recent MAVLink heartbeat from the flight
controller. If the link goes stale the command controls disable
themselves. The interface shows link freshness continuously rather than
only reporting failure after a command is rejected, so the operator knows
before pressing anything whether the aircraft is listening.

## Telemetry displayed

Armed state, flight mode by name, battery voltage and remaining
percentage, GPS fix quality with satellite count, and link freshness.
Flight controller status messages are shown as text, which is how arming
checks and refusals reach the operator in the controller's own words.

> Those messages arrive split across several MAVLink frames. An earlier
> version displayed each fragment as it arrived, so an arming refusal
> appeared as unreadable fragments. The interface now reassembles them by
> sequence and displays only complete messages, with a short timeout so a
> lost fragment does not suppress the rest.

## Commands

| Command | Notes |
|---------|-------|
| Arm / Disarm | Confirmation dialog |
| **Force disarm** | Always visible, never gated. The one control that must work when everything else has gone wrong |
| Motor test | Single motor, low throttle, fixed duration. The props-off verification |
| Mode: STABILIZE / GUIDED | |
| Takeoff | Guided mode, target altitude |
| Reposition | Guided mode, to a coordinate |
| Return to launch | Also issued automatically by the battery watchdog |

Every command encoding is covered by unit tests against the MAVLink wire
format, so the bytes are verified without hardware. Force disarm being
ungated is a deliberate asymmetry: every other control can be locked out
by a stale link, and that one cannot.

## What the interface refuses to do

Worth stating, as it is a design position rather than an omission:

- It never commands a volunteer drone. Those carry a communication
  module and their flight is their pilot's responsibility. The fleet
  board shows volunteer rows as pilot advisories, text for a human to
  act on, not commands.
- It does not hide the props-off policy. The interface labels the
  operating mode so nobody can be unaware of which regime they are in.

---

# Figures to capture

| Figure | Shows | How |
|--------|-------|-----|
| 4.x | The assembled system drone, whole aircraft | Photograph, props off, on the bench |
| 4.x | The Pi and adapter mounted on the airframe | Photograph, top or side |
| 4.x | Pi to flight controller wiring | Photograph or diagram |
| 4.x | System drone block diagram | Diagram: flight domain and node domain side by side, with the serial link between them and the two power domains marked |
| 5.x | Drone control tab, connected | Screenshot: telemetry populated, DISARMED, link fresh |
| 5.x | Flight controller messages panel | Screenshot: a reassembled arming check message |

The block diagram is the important one. It is the figure that shows at a
glance that this aircraft is two systems sharing a frame, which is the
whole argument of section 4.2.4.

---

# Verification checklist before submitting

Six items, each a factual claim I could not confirm from the code:

- [ ] Flight controller firmware and version, and that it speaks MAVLink
- [ ] Frame diagonal in millimetres
- [ ] GPS module exact part number
- [ ] Battery cell count actually used, 3S or 4S
- [ ] How the Raspberry Pi is powered, and whether it shares the flight battery
- [ ] All-up weight with the node fitted, if the airframe's payload limit is to be discussed
