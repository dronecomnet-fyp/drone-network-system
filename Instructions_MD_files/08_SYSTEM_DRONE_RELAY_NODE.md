# 08 SYSTEM DRONE RELAY NODE (THIRD PI ABOARD THE SYSTEM DRONE)

Context: the fleet is now 2 full communication modules on the volunteer
drones (DRONE_A, DRONE_B) plus the system-owned drone. The third Raspberry
Pi is spare, and the team decision is to mount it on the system drone as
node DRONE_S. This solves the control problem cleanly, because the drone's
own ESP32-WROOM bridge is 2.4 GHz only (cannot join the 5 GHz user AP) and
ESP32 chips do not support IBSS ad-hoc mode at all (station, softAP, and
ESP-NOW only), so without a Pi aboard the system drone has no way into the
mesh.

## What DRONE_S is

A FULL node, identical software to A and B, built from the same image and
setup script (file 01) with its own `drone_s.conf`:
- Same FastAPI backend, same SQLite database, same sync daemon: messages,
  gs_messages, personnel, announcements, and checkins all replicate to and
  from DRONE_S exactly like the other nodes. Nothing is cut down.
- Same 5 GHz user AP (SSID RESCUE_S, 10.42.0.1) and captive portal: bonus
  victim coverage wherever the drone lands, and it gives the GCC a direct
  connection path to this node.
- Same 2.4 GHz AR9271 on the IBSS cell at 10.99.0.3.
- PLUS one extra service: a MAVLink gateway between the flight controller
  and the network (below).
- MINUS (by default) the aux module: only two aux sets exist, and they
  belong to the volunteer modules. Set AUX_SERIAL empty in drone_s.conf;
  aux_bridge stays disabled and /health reports aux: absent. Consequences:
  no LoRa fallback beacon and no GPS time on this node initially. The FC
  has its own GPS, so a later optional task feeds MAVLink GPS/time into
  node_health and the clock (see Clock section).

## Decision record (D7, per project rule 7)

Chosen: third Pi flies on the system drone as a full mesh node and MAVLink
gateway.
Why: it is the only configuration that lets the GCC reach the system drone
through the volunteer drones' modules, it adds a third DTN node back into
the network, and it reuses the exact node software with zero forks.
Alternatives considered:
- Direct-only control via the drone's existing ESP32 bridge: works on the
  bench, but range-limited to one WiFi hop, requires the laptop to leave
  the module network (or carry a second WiFi adapter), and the drone never
  joins the mesh. Kept only as an optional backup link.
- Third Pi as a ground/HQ node: rejected, the GCC laptop already fills the
  ground role, and it leaves the control problem unsolved.
- Re-band a volunteer module's user AP to 2.4 GHz so the drone ESP32 could
  join it: rejected, it puts users on the same band as the DTN link
  (master plan R2 interference) and contradicts the approved design.

## Hardware checklist (verify before any software work)

1. Pi 4B number three: available (confirmed by team).
2. AR9271 adapter number three: CHECK INVENTORY. Required for mesh
   membership. If missing, buy the same chipset/model as the other two so
   file 01's driver steps hold unchanged.
3. Power (decision, rule 7):
   - Chosen initially: the standard Battery A architecture (2S pack +
     regulator) identical to the other nodes. Why: uniform power design
     across all nodes, comm power independent from flight power, and the
     battery capacity document's calculations carry over unchanged.
   - Alternative: 5 V BEC tap from the drone's flight battery. Saves the
     2S pack's mass but couples the node's uptime to the flight battery
     and invalidates the per-node power documentation. Revisit ONLY if the
     lift test fails on mass.
4. LIFT TEST (mandatory gate): hover the system drone with a dummy payload
   equal to the full module mass (weigh the real stack: Pi + case + AR9271
   + Battery A + wiring). Record hover throttle percentage and achievable
   flight time in docs/test_log.md. If hover throttle is uncomfortably
   high or flight time collapses, fall back to the BEC option and re-test.
   Do not guess numbers; measure (project rules 4 and 6).
5. FC serial wiring: Revo Mini telemetry UART to the Pi via a USB-serial
   adapter (3.3 V logic). The exact Revo Mini port-to-SERIALn mapping must
   be read from the ArduPilot Revo Mini page during file 04 Stage 0; do
   not guess port names. Direct Pi GPIO UART wiring is possible but the
   USB adapter is simpler and keeps the Pi's UART free; note the choice.
6. The existing ESP32-WROOM bridge becomes optional. Keep it during
   bring-up as a backup link; once the relay path passes tests, removing
   it saves mass (decision for the team, record either way).

## MAVLink gateway service

- Install mavlink-router (or MAVProxy if packaging is easier on Bookworm;
  pick one at implementation time and record why) as
  rescue-mesh-mavgw.service, enabled only when DRONE_CONTROL=true in
  node.env.
- Endpoints: serial device (FC_SERIAL, baud from Stage 0 findings) on one
  side; UDP server on 0.0.0.0:14550 on the other. That single UDP endpoint
  serves BOTH control paths below.
- Log MAVLink traffic summaries to the journal, not full packet dumps.

## Two control paths for the GCC

Path 1, direct: laptop joins RESCUE_S, GCC targets 10.42.0.1:14550.
Lowest latency, use for bench work and whenever the system drone is the
nearest node.

Path 2, mesh relay: laptop joins RESCUE_A or RESCUE_B, GCC targets
10.99.0.3:14550. Traffic path: laptop -> volunteer Pi (wlan0) -> IBSS
(wlan1) -> DRONE_S. Requirements on the volunteer Pis:
- IPv4 forwarding enabled. NetworkManager's shared mode usually enables
  forwarding and NAT for the shared subnet; VERIFY on the rebuilt image,
  and if NAT toward wlan1 is not already present, add an explicit
  masquerade rule (nftables) from 10.42.0.0/24 out wlan1. Encode whichever
  is needed into deploy/ so it is reproducible.
- Laptop needs no manual route: NM shared mode hands out 10.42.0.1 as the
  default gateway, so packets to 10.99.0.3 already go to the Pi.
Verification commands, in order: from the laptop `ping 10.99.0.3`, then
point the GCC (or mavproxy) at udp:10.99.0.3:14550 and confirm heartbeats.

## Control rules over the relay (safety, non-negotiable)

- Flight commands travel ONLY over a live end-to-end link. Nothing is ever
  queued DTN-style for later delivery to the drone. The mesh's
  store-and-forward applies to messages, never to control.
- The GCC greys out all command buttons whenever the MAVLink heartbeat is
  older than 2 seconds (file 04 already specifies this gate).
- The FC's GCS-loss failsafe (RTL) must be configured and bench-verified
  before any armed relay test (file 04 safety gates apply unchanged).
- Latency over two WiFi hops is fine for telemetry and guided commands.
  Manual stick flying over the relay is prohibited; the RC pilot remains
  the manual override at all times.

## Clock on DRONE_S (no aux module)

Initially: time_source stays "relative" on this node, exactly as design v3
handles pre-fix messages. Optional follow-up task once file 04 Stage 1
works: read SYSTEM_TIME from the FC's MAVLink stream in the gateway
service and set the clock the same way aux_bridge does (shared sudoers
mechanism from file 02), flipping clock_source to gps. Keep it optional;
do not block the relay milestone on it.

## Acceptance for file 08

1. DB parity: a message submitted on RESCUE_S and a personnel record
   created on DRONE_A both appear on all three nodes within two sync
   cycles (proves DRONE_S is a first-class node).
2. Direct path: GCC on RESCUE_S shows live FC telemetry (props off).
3. Relay path: GCC on RESCUE_A shows the same telemetry via 10.99.0.3.
4. Link-cut drill (props off): take DRONE_S's wlan1 down mid-session; GCC
   controls grey out within 2 seconds and the FC registers GCS loss.
5. Lift test logged with measured mass, hover throttle, and flight time,
   and the power decision (Battery A vs BEC) recorded with the measurement
   that justified it.
