# Paste-ready text: Chapter 4 split, and the drone control interface

Everything below is final prose. Two figures, both of which you already
have. Five things to fill in, marked `«like this»`, listed at the end.

---

## PASTE 1: retitle your existing 4.1

Change the heading to:

> **4.1 Volunteer Communication Module**

and insert this as the first paragraph, before your existing text:

> The communication module described in this section is designed to be
> carried by an aircraft that the project neither owns nor modifies. It
> shares nothing with its host but a mounting point: it does not read the
> flight controller, does not use the aircraft's radio, and cannot
> influence flight in any way. This constraint shapes every decision that
> follows, because it means the module must supply its own power, its own
> positioning, and its own radios rather than borrowing any of them from
> the aircraft. Section 4.2 describes the one aircraft in the fleet where
> that constraint is deliberately lifted.

Then move your existing 4.1 subsections down so they sit under 4.1.

---

## PASTE 2: the whole of 4.2

> ## 4.2 System Drone
>
> ### 4.2.1 Purpose
>
> The volunteer model described in Section 4.1 deliberately asks nothing
> of the host aircraft. That is its principal strength, and also its
> limit: a volunteer drone can carry the network, but the system cannot
> command it. Coordinated placement, station keeping and automated return
> are therefore impossible to demonstrate on a volunteer node, because the
> aircraft answers to its own pilot.
>
> DRONE_S exists to close that gap. It runs the same node software as the
> volunteer nodes, making it a full participant in the mesh, and in
> addition it exposes its flight controller to the Ground Control Center.
> It is the only aircraft in the fleet that the system can both
> communicate *through* and issue commands *to*.
>
> This distinction bounds the claims made later in this report. The fleet
> management logic described in Chapter 5 is demonstrated across an
> arbitrary number of drones in simulation, and commanded for real on
> exactly one.
>
> ### 4.2.2 Airframe and propulsion
>
> The aircraft is a pre-built carbon fibre quadcopter that was adopted
> rather than designed. This was a deliberate scope decision: the
> contribution of this project is the communication payload and the
> network it forms, and designing an airframe would have consumed
> significant time without advancing that contribution.
>
> | Component | Specification |
> |-----------|---------------|
> | Frame | Carbon fibre, X configuration, «FRAME» mm class |
> | Motors | 4 x EMAX RS2205, 2300 KV brushless |
> | Electronic speed controllers | 4 x 40 A brushless, 2 to 4S compatible, each with a 5 V / 3 A BEC |
> | Propellers | Gemfan Hurricane 51499, three blade, 5.1 in diameter, 4.99 in pitch |
> | Flight battery | «CELLS»S LiPo |
> | Power connector | XT60 male, 14 AWG silicone lead |
>
> One property of this configuration deserves comment, because it
> constrains what may honestly be claimed from it. A 2300 KV motor driving
> a three blade 5.1 inch propeller is a high thrust, short endurance
> combination, characteristic of agile five inch quadcopters rather than
> of endurance platforms. The airframe was selected for availability, not
> for loiter time. Flight endurance figures obtained from this aircraft
> should therefore not be generalised into claims about the endurance of
> the communication network, which is governed by the module's own
> battery as analysed in Section 4.1.
>
> ### 4.2.3 Flight control, navigation and the companion computer
>
> | Component | Role |
> |-----------|------|
> | OpenPilot CC3D Revolution Mini | Flight controller: stabilisation and flight dynamics |
> | «GPS» GPS module, ceramic patch antenna | Position hold and return to launch |
> | Raspberry Pi 4 Model B | Companion computer: node software and MAVLink gateway |
>
> The flight controller runs firmware exposing a MAVLink telemetry and
> command interface, «FIRMWARE», which is the protocol the Ground Control
> Center speaks throughout.
>
> The Raspberry Pi is connected directly to the flight controller over a
> USB serial link. The donor build included a separate wireless bridge
> module for telemetry; it is not used in this configuration, because the
> companion computer is already present on the aircraft and connecting it
> directly removes an intermediate hop without requiring any change to the
> flight controller's own firmware.
>
> ![System drone with components](media/«FIGURE_DRONE».png)
>
> *Figure 4.x: The assembled system drone, showing the flight controller,
> GPS module, and the Raspberry Pi 4 with its USB WiFi adapter mounted as
> the communication node. Propellers removed, in accordance with the
> safety policy in Section 4.2.6.*
>
> ### 4.2.4 One aircraft, two independent roles
>
> DRONE_S runs the identical node software described in Chapter 5. From
> the perspective of the mesh it is an ordinary peer: it serves a user
> access point, holds a replica of every synchronised table, and
> participates in synchronisation exactly as the volunteer nodes do.
> Adding flight control required no fork of the node software.
>
> The second role is provided by one additional service, the MAVLink
> gateway, which performs two distinct functions.
>
> The first is a **transparent control bridge**. Raw MAVLink bytes are
> forwarded unmodified in both directions between the flight controller's
> serial link and a UDP endpoint. Forwarding bytes rather than parsing and
> re-emitting them ensures that a command cannot be altered in transit by
> the gateway itself.
>
> The second is a **read-only telemetry tap**. The gateway parses a copy
> of the controller-to-ground stream and extracts three messages into the
> node's own health record:
>
> | MAVLink message | Extracted for |
> |-----------------|---------------|
> | `GPS_RAW_INT` | Position, fix quality, satellite count |
> | `SYS_STATUS` | Flight battery voltage |
> | `SYSTEM_TIME` | Setting the system clock from GPS time |
>
> The third row resolves a problem specific to this node. DRONE_S carries
> no Auxiliary Module, and therefore has no INA3221, no LoRa radio and no
> independent GPS receiver. Without the telemetry tap it would have no
> position to report and no trusted time source, leaving it permanently on
> relative timestamps. Taking these values from the flight controller
> means the aircraft's own navigation sensors serve the communication node
> as well, which is a direct benefit of siting the companion computer on
> the flight controller rather than alongside it.
>
> The absence of an Auxiliary Module also carries three costs, which are
> stated here as accepted limitations rather than omissions:
>
> - **No LoRa fallback beacon.** If this node's Raspberry Pi fails, the
>   node becomes entirely silent. A volunteer node in the same situation
>   continues to report its position and status over LoRa, as described in
>   Section 4.1. DRONE_S cannot.
> - **No independent battery monitoring.** The voltage reported by this
>   node is the flight battery, observed through the flight controller,
>   rather than a dedicated measurement of the communication payload.
> - **No Bluetooth Low Energy advertisement.** The Emergency Application
>   cannot discover this drone passively. Affected individuals can still
>   connect to its access point directly.
>
> ### 4.2.5 Power
>
> The system drone has two power domains. The flight domain supplies the
> motors, speed controllers and flight controller from the LiPo battery
> through the XT60 connector. The node domain supplies the Raspberry Pi
> and its USB WiFi adapter, and is «POWER».
>
> The node domain carries a requirement established empirically during
> field testing and reported in Chapter 6. A Raspberry Pi 4 operating
> alongside the AR9271 USB WiFi adapter cannot be reliably sustained by a
> supply unable to deliver approximately 3 A. Below that threshold the
> adapter browns out and detaches from the USB bus, and the resulting
> failure is silent from the application's point of view: synchronisation
> continues to report success because a node with no visible peers has
> nothing to synchronise and cannot distinguish that condition from
> genuine quiescence.
>
> This threshold is relevant to the system drone because the speed
> controllers provide a 5 V / 3 A BEC, which sits at the boundary of the
> measured requirement rather than comfortably above it. Any configuration
> drawing the node's power from that source operates without margin
> against a failure mode the project has already observed.
>
> ### 4.2.6 Interfaces and safety policy
>
> | Interface | Connects | Purpose |
> |-----------|----------|---------|
> | USB serial | Pi to flight controller | Bidirectional MAVLink |
> | UDP port 14550 | Gateway to Ground Control Center | Control and telemetry endpoint |
> | Onboard WiFi | Raspberry Pi | 5 GHz user access point |
> | USB 3.0 | Pi to AR9271 adapter | 2.4 GHz mesh backbone |
> | microSD | Raspberry Pi | Operating system, database, logs |
>
> All flight command functionality is verified **with the propellers
> removed**. Commands are confirmed to reach the flight controller, motors
> are confirmed to respond during controlled motor tests, and the battery
> watchdog is confirmed to trigger a return-to-launch command, all on the
> bench. Free flight is outside the scope of this project and awaits a
> deliberate airworthiness and safety procedure.
>
> This is a scope boundary rather than an incomplete implementation. The
> command path is fully implemented and tested; the decision not to fly is
> separate and deliberate.

---

## PASTE 3: the drone control interface, for Chapter 5

Put this with your other Ground Control Center screens. **It replaces the
paragraph in the current draft describing this tab as a preparation
interface**, which is no longer accurate.

> ### 5.x Drone Control Interface
>
> This screen provides monitoring and, under the safety conditions stated
> in Section 4.2.6, control of the system drone through the MAVLink
> gateway described in Section 4.2.4. It applies exclusively to DRONE_S.
> Volunteer drones carry a communication module only, and the interface
> never issues a command to one.
>
> ![Drone control interface](media/«FIGURE_UI».png)
>
> *Figure 5.x: The drone control interface, showing live telemetry from
> the flight controller and the command palette. Force disarm remains
> available at all times.*
>
> **Connection model.** The operator's laptop reaches the gateway over UDP
> by one of two routes, and the interface identifies which applies. When
> the laptop is joined to the system drone's own access point the
> connection is direct. When it is joined to a volunteer node instead, the
> connection is relayed across the mesh backbone to the system drone.
> Both are live paths. Flight commands are never stored and forwarded,
> which is a deliberate rule rather than an implementation constraint: a
> command that arrives late is more dangerous than one that never arrives,
> because the operator has moved on and the aircraft has not.
>
> **Heartbeat gating.** Every command is conditional on a recent MAVLink
> heartbeat from the flight controller. If the link becomes stale the
> command controls disable themselves automatically. Link freshness is
> displayed continuously rather than reported only after a command has
> been rejected, so the operator knows before acting whether the aircraft
> is listening.
>
> **Telemetry.** The interface displays armed state, flight mode by name,
> battery voltage and remaining capacity, GPS fix quality with satellite
> count, and link freshness. Status messages generated by the flight
> controller are shown as text, since arming checks and refusals reach the
> operator in the controller's own words. These messages arrive divided
> across several MAVLink frames; the interface reassembles them in
> sequence and displays only complete messages, so that a refusal appears
> as a readable sentence rather than as fragments.
>
> **Commands.** Arm and disarm, both requiring confirmation; a single
> motor test at low throttle for a fixed duration, which is the
> propellers-removed verification procedure; flight mode selection between
> stabilised and guided; guided takeoff to a target altitude; guided
> reposition to a coordinate; and return to launch, which is also issued
> automatically by the battery watchdog when the flight battery falls
> below a configured threshold.
>
> Force disarm is deliberately exempt from heartbeat gating and remains
> available at all times. This asymmetry is intentional: every other
> control may be locked out by a stale link, and the one command required
> when the situation has already deteriorated must not be.
>
> Every command encoding is verified against the MAVLink wire format by
> automated tests, so the transmitted bytes are validated without
> requiring the aircraft.

---

## The five fill-ins

Search for `«` and replace:

| Marker | What to put |
|--------|-------------|
| `«FRAME»` | Frame diagonal in mm, e.g. 220. Measure motor centre to opposite motor centre |
| `«CELLS»` | 3 or 4, whichever battery you fly |
| `«GPS»` | GPS module name. If unsure, write "u-blox class" |
| `«FIRMWARE»` | The firmware on the CC3D. If unsure, delete the clause "«FIRMWARE», " and leave the sentence reading "...exposing a MAVLink telemetry and command interface, which is the protocol..." |
| `«POWER»` | One of: "supplied by a dedicated battery, independent of the flight battery" or "derived from the flight battery through the speed controllers' BEC" |
| `«FIGURE_DRONE»`, `«FIGURE_UI»` | Your two image filenames |

If you are unsure about `«FIRMWARE»`, deleting it is the right move. The
sentence stays true without it, because it is then a statement about the
interface the gateway uses rather than a claim about a specific firmware
build.
