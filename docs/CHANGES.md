# CHANGES: decisions and figure changes vs earlier project documents

Project rule 5: any implementation finding that changes a figure or decision
recorded in an earlier document (design v3, battery capacity decision doc,
Phase 1 security docs) is flagged here, never silently drifted.

## 2026-07-11 Phase 2 foundation build (packages 01, 02, 03 + file 09)

1. DTN layer 2 changed from design v3 wording (wlan1 AP <-> station cycling)
   to an always-on open IBSS cell with static IPs (master plan D2, team
   approved 2026-07-11). Reasons: no role switching, any pair in range syncs
   at any time, removes the Phase 1 timing fragility. Rejected alternatives
   recorded in master plan D2. The station-cycling design remains the
   documented fallback if IBSS fails T2/T3, per file 01 step 5.

2. Victim plane moved from self-signed HTTPS 8443 to plain HTTP port 80
   (file 09 F3). Reason: victims hitting certificate warnings on a captive
   portal is a usability cost with no authentication value to them; in the
   threat model, victim-message integrity (protected by signing at ingest)
   and availability outrank confidentiality. Plaintext-over-air on the open
   victim plane is a written accepted risk. HTTPS 8443 stays for every
   authenticated plane (rescue, HQ, sync). This supersedes the Phase 1
   SECURITY_FEATURES.md description of the victim flow.

3. Single fleet-wide signing secret replaced by per-purpose keys derived
   with HKDF-SHA256 from one master secret (file 09 F2): K_msg for record
   signatures, K_sync for inter-node auth and presence beacons, K_token for
   session tokens. Reason: one captured node no longer owns every trust
   purpose at once. Physical capture stays the residual risk; the response
   is the existing rotation runbook. Per-node Ed25519 identities are
   recorded as future work, not this phase.

4. TLS provisioning changed from per-node plain self-signed certificates to
   a fleet CA issuing per-node certificates (file 09 plane 2). Reason: the
   Phase 1 app behavior (accept any certificate for 10.42.0.1) was not
   pinning; apps will embed the fleet CA and fail closed against evil-twin
   APs. App-side changes land in packages 04/05.

5. Inter-node mTLS demoted to a documented option, off by default (file 09
   D1). Reason: with per-record HMAC verification on every synced row plus
   X-Node-Auth, mutual TLS adds certificate lifecycle work for marginal
   gain in a 3-node fleet. The env switches remain in the backend.

6. Victim message E2E encryption (fleet keypair) demoted to off by default
   (file 09 D2). Reason: the private key pasted into every rescuer phone is
   a shared secret in asymmetric clothing; a mismanaged key mid-disaster
   makes pleas for help unreadable. Capability kept behind its existing env
   flags for the thesis tradeoff discussion.

7. Message schema replaced by design v3 schema (msg_id, content, user_lat,
   user_lon, node_lat, node_lon, timestamp ISO 8601 UTC, time_source,
   node_id, status, claimed_by, synced_from + Phase 1 security columns).
   No migration from Phase 1 databases: the fleet is rebuilt together
   (master plan D1/R6), a prototype-phase decision stated in the thesis.

8. Announcements read access decision (file 02 left it open): GET
   /announcements is rescue-scoped (session token or any role key), not
   public. Reason: announcements are operational guidance for rescue
   personnel; the victim plane has no read-back by design (file 09 plane 1).

9. gs_messages gain an HMAC signature column and sync fleet-wide, fixing
   the Phase 1 gap where field reports never left the node they were filed
   on (master plan section 2).

## 2026-07-13 Aux module pin correction (bench finding, rule 5)

10. LoRa MISO moved from D9 to D0 (GPIO2) on the XIAO ESP32-C3. File 03's
    pin table and the firmware constant both listed MISO on D9; on the
    first fully-soldered module, SPI reads from the RFM95 failed on D9 and
    worked on D0 (LoRa.begin() returned false with D9, true with D0).
    Fixed in firmware/aux/src/main.cpp (constant + header pin table) and
    the Windows bring-up runbook troubleshooting table. Consequence: every
    XIAO signal pin is now allocated; D0 is no longer the spare pin listed
    in file 03. This supersedes the "LoRa MISO D9" entry in file 03's pin
    map; update design v3/v4 accordingly. Confidence: High (reproduced on
    the bench). All other pins in file 03's table were confirmed correct.

## 2026-07-16 System drone / MAVLink descope (hardware reality, rule 5)

11. The system drone (AeroSync 5) is confirmed to speak MAVLink already
    (CC3D Revo Mini + ESP32 DroneBridge), so no ArduPilot reflash was
    needed. Master plan D5 Stage 0 is satisfied; see docs/DRONE_LINK.md.

12. DRONE_S is NOT a DTN mesh node this phase, superseding file 08's
    "third Pi as DRONE_S at 10.99.0.3 on the IBSS backbone" design. The
    system drone's Pi 4 has a single onboard radio and no AR9271, so it
    cannot join the 2.4 GHz mesh AND talk to the 2.4 GHz ESP32 at once.
    Control is therefore DIRECT only (GCC over the DroneBridge AP); the
    mesh-relayed control path is documented as future work needing a
    second radio. Reasoning (incl. why time-slicing a live control link
    is disqualified) in docs/DRONE_LINK.md section 3. The DTN mesh and
    user APs are unaffected.

13. Drone control goal descoped to PROPS-OFF ground testing: motor test
    from the GCC as the command-pipeline proof, not armed flight (no RC
    transmitter available, no tuning time). GCS-only arming params are
    bench-only and not airworthy (DRONE_LINK.md section 4).

14. MAVLink 2 packet signing (file 09 plane 4 layer 2) is NOT implemented
    this phase: the Dart MAVLink library's outbound signing support is
    unconfirmed. Compensating control is network isolation of the
    point-to-point DroneBridge control link (plane 4 layer 1); signing is
    recorded as honest residual risk / future work (DRONE_LINK.md sec 5).

15. GCC Drone tab implemented (was a locked Stage 0 placeholder): live
    MAVLink telemetry and a command palette (arm/disarm, always-on force
    DISARM kill, per-motor test, mode set) with every control gated on a
    heartbeat fresher than 2 s. gcc_app now depends on dart_mavlink.

## 2026-07-18 System drone becomes a full node (reverses items 12-14, rule 5)

16. A second AR9271 was added to the system drone's Pi, so DRONE_S now has
    two radios and IS a full DTN mesh node after all: onboard 5 GHz
    RESCUE_S AP (10.42.0.1) + AR9271 2.4 GHz IBSS peer (10.99.0.3), same
    node software as A/B. This REVERSES item 12: the mesh-relayed control
    path is now available (GCC on RESCUE_A/B -> volunteer forwards -> mesh
    -> 10.99.0.3:14550), and it is live MAVLink, not DTN store-and-forward.

17. The ESP32 DroneBridge is REMOVED. The Pi wires directly to the CC3D
    over serial (3.3 V GPIO UART /dev/serial0, or a USB-TTL /dev/ttyUSB0),
    no reflash of the FC or anything else. New folder mavlink_gateway/ with
    mav_gateway.py: a self-contained pyserial+pymavlink transparent
    serial<->UDP bridge on 0.0.0.0:14550. Chosen over mavlink-router
    (not in Bookworm apt) and MAVProxy (heavier); rationale in
    mavlink_gateway/README.md. Tested end to end by tools/mavgw_pty_test.py
    (9 checks, no hardware).

18. DRONE_S self-locates from the flight controller (it has no aux module).
    The gateway taps the FC MAVLink read-only: GPS_RAW_INT -> /health GPS,
    SYS_STATUS -> flight-battery voltage, SYSTEM_TIME -> sets the Pi clock
    from GPS time (same narrow sudoers date mechanism as aux_bridge). So
    the drone's own GPS gives DRONE_S position + time with no INA3221, no
    LoRa, no separate GPS module.

19. Item 14 partially addressed: MAVLink 2 signing still not implemented,
    but the relay path is now firewalled (nftables-drone-s.nft restricts
    UDP 14550 to 10.42.0.0/24 and the volunteer mesh addresses), which is
    file 09 plane 4 LAYER 1. Signing (layer 2) remains future work.

## 2026-07-21 Phase 2 mission layer (M7: planning, live ops, product site, AI)

20. New synced table personnel_locations (M7d): rescuers' last known
    positions replicate fleet-wide. Chosen shape: latest-per-personnel,
    newest-signed-updated_at wins (the personnel table pattern), NOT the
    append-only checkin pattern. Reason: the GCC needs one current marker
    per rescuer, not a history; upsert-by-personnel_id keeps the table small
    and the sync merge simple. Rejected: append-only + GROUP BY MAX at read
    (works, but grows without bound for a live-position use case). Follows
    all existing controls: K_MSG record signature, verified at sync;
    identity taken from the session token, never the request body. The table
    is created automatically at service start (CREATE TABLE IF NOT EXISTS),
    no migration; see deploy/node_update_locations.html.

21. Rescuer location tracking is FOREGROUND-ONLY (M7d), an accepted
    limitation. The rescue app heartbeats every ~90 s only while logged in
    and in the foreground; background and logged-out send nothing. Reason:
    battery. Continuous background tracking (WorkManager foreground service)
    is documented future work; the emergency_app already has the pattern
    (location_logger.dart) if it is ever wanted. Consequence: the operator
    sees each rescuer's LAST known position with its age, never a live
    stream. No new Android permissions (FINE/COARSE already declared).

22. Product data moves to a real hosted backend (M7c): a Supabase project
    (PostgREST + row-level security) backs the product website and the GCC
    unit-spec lookup. Decision: the anon key is public by design (embedded
    in the site and enterable in the GCC); RLS is the access control (anon
    reads products/units, insert-only on quotes; the service_role key is
    never committed). Supersedes the earlier assumption that product specs
    would be hard-coded; the GCC now fetches a unit's specs by ID online and
    caches them into the mission so the field stays offline.

23. Fleet management is a two-mode coordination layer (M7f), not multi-drone
    flight. Reality (file 08 scope guard) is unchanged: only DRONE_S has a
    flight controller the GCC commands. So "manage 10 drones" is handled by
    a DEMO simulator (any count, exam-safe) that flies each drone, drains a
    modelled battery, and auto-returns before a 1.5x-home-energy reserve is
    spent; the REAL path (DRONE_S only) uses the existing heartbeat-gated
    MAVLink with added takeoff / DO_REPOSITION / NAV_RETURN_TO_LAUNCH and a
    per-cell-voltage watchdog. FLIGHT POLICY UNCHANGED: props-off bench
    verification only; free flight waits for the operator's explicit safety
    clearance. Inventory accounting ("Deployed X / Y available") disables
    Deploy when the pool is empty, so the platform manages the whole
    operation even though one drone is ours. Battery/cruise figures are
    tunable estimates (confidence Low/Moderate, labelled in code).

24. The AI deployment advisor (M7e) speaks the OpenAI-compatible chat API,
    not the Anthropic API. Reason: a FREE tier was required (Groq,
    OpenRouter). Endpoint/model/key are entered in Settings and never
    committed. The model only PROPOSES placements as JSON; the app validates
    them (point-in-polygon, count, mesh connectivity, one system drone,
    radius clamp) and the operator approves on the map. The AI never
    commands a drone, and planning is online-only (HQ); the field plans
    manually. This supersedes the earlier plan note that assumed the
    Anthropic API; both are reachable through the same OpenAI-compatible
    code path (Anthropic via OpenRouter) with no second implementation.

25. PlanState (advisory markers, item from file 04) is superseded by
    MissionState (M7b): a mission holds identity, disaster type, challenges,
    an area polygon, a resource inventory (drones by our unit ID, volunteer
    drones with one of our modules attached, or minimal), a product-spec
    cache, and named deployments, saved as one local JSON file. Legacy
    operation-plan files still import (as one approved deployment), so no
    prior evidence is lost. Placements remain advisory: activating a
    deployment never commands a drone (the fleet manager, item 23, is the
    only thing that does, and only for DRONE_S, props-off).
