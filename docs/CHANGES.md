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

## 2026-07-24 Battery B moves off the INA3221 to the ESP32-C3 ADC (rule 5)

> WITHDRAWN, never deployed. Item 30 (2026-07-26) reverses this: Battery B
> is wired to INA3221 CH2 after all. Item 26 is kept here rather than
> deleted because rule 5 is about an honest record of decisions, including
> the ones that were reversed before reaching hardware. No module was ever
> flashed with the ADC firmware, so no field behaviour ever depended on it.

26. Battery B is now read by the ESP32-C3's own ADC from the XIAO battery
    pad, not INA3221 channel 2. Reason (hardware reality): only CH1
    (Battery A) is wired to the INA3221; Battery B sits on the XIAO battery
    pads, so the module reads it directly with analogReadMilliVolts through
    a divider (PIN_BATT_B_ADC / BATT_B_DIVIDER in firmware/aux1/src/main.cpp).
    Consequence: Battery B reports VOLTAGE ONLY (bat_b_v); it has no current
    reading (bat_b_ma is always null) because a plain ADC cannot measure
    current, so the duty-cycle test (TESTS.md test 6) now measures current
    externally. This supersedes design v3's "INA3221 CH2 = Battery B" channel
    map; CH2/CH3 are unused now. Open hardware item: the XIAO's ADC1 pins
    (D0/D1/D2) are all used by LoRa, so PIN_BATT_B_ADC defaults to D0 as a
    PROVISIONAL, compile-safe placeholder and must be moved to a freed ADC
    pin (or an external ADC) before the reading is trusted. Confidence:
    the mechanism is High; the specific pin is Low pending the wiring choice.

## 2026-07-24 LoRa fallback drones surface as alerts (GCC + rescue app)

27. A drone whose Raspberry Pi lost power is heard only through its aux
    module's LoRa beacon and is reported as a DEGRADED node in /health.
    Previously that only showed as a card on the GCC Nodes tab. It is now
    elevated to a red alert banner: in the GCC on both the Live Ops
    dashboard and over the Map (widgets/degraded_alert.dart, fed by the
    already-replicated degraded_nodes list), and in the rescue app across
    every tab (widgets/alert_banner.dart, driven by a new AlertsProvider
    that polls the public /health every 15 s). Reason: a downed drone is a
    coverage hole that both HQ and field rescuers must see immediately, not
    a detail buried in a tab. No firmware, backend, or schema change: this
    consumes the existing fallback-beacon path. Note: /health node_health
    is per-node and not replicated, so the alert reflects what the node the
    app is talking to has heard, consistent with the rest of the health
    view.

## 2026-07-24 Rescue app gains the ops map (phone-facing, task D)

28. The operations map, previously GCC-only by design, now also ships as a
    tab in the rescue app so a field team sees victims, teammates, and
    drones on one picture. It uses the same flutter_map engine as the GCC
    but ships NO MBTiles file: markers render on flutter_map's plain
    background (the "markers on a plain grid" view the user chose), which
    still pans, zooms, and uses true lat/lon. Layers: victim messages
    (red new / green claimed) and emergency checkins (blue, orange for
    SOS); other rescuers' last reported location (teal, named) plus the
    logged-in rescuer as a blue dot (from the M7d personnel_locations
    feed); the connected node's GPS (indigo) and DEGRADED nodes at their
    last LoRa-beaconed position (red). No backend or schema change: it
    consumes existing endpoints (/messages, /checkins, /personnel-locations,
    /health) through two new APIService wrappers. Battery note: the map
    polls every 12 s but only while its tab is on screen (the app builds
    only the selected screen; the poll timer starts in initState and is
    cancelled in dispose), so it costs nothing on the other tabs. Limit:
    healthy peer drones carry no GPS in /health (node_health is not
    replicated), so only the connected node and fallback nodes have plotted
    positions, same as the GCC map.

## 2026-07-24 GCC "Field Share": local download point for the field (task E)

29. New GCC tab that turns the ground laptop into an offline download
    point. At a disaster site there is no internet and no app store, so
    getting the rescue app and offline region maps onto personnel phones
    was an unsolved gap. The operator copies the field bundle (rescue-app
    APK, .mbtiles region maps, anything else) onto the laptop from a USB
    stick beforehand; on site everyone joins one local Wi-Fi (a travel
    router or the laptop hotspot); the operator points Field Share at that
    folder and taps Start. The GCC then runs a small local HTTP server
    (services/distribution_server.dart, a dart:io HttpServer on port 8080)
    and shows a link plus a QR code (screens/distribution_screen.dart). A
    rescuer scans the QR, opens a plain self-contained web page in their
    phone browser, and taps to download. The server lives as a root
    provider so it keeps running while the operator uses other tabs.
    Security posture: it serves ONLY the chosen folder's top-level files
    over plain HTTP on the LOCAL network; there is no upload path, filenames
    are validated so a request cannot escape the folder, and this is a
    deliberate hand-out of public installers/maps, not sensitive data. New
    dependency: qr_flutter (pure Dart, offline). Platform note: the macOS
    dev build already carries the com.apple.security.network.server
    entitlement (DebugProfile) so the demo works under `flutter run`; the
    Windows delivery build needs no entitlement. Operator steps are written
    up in docs/FIELD_SHARE.md.

## 2026-07-26 Battery B returns to CH2, both channels bidirectional (rule 5)

30. Battery B is wired to INA3221 channel 2 after all, so item 26 (the
    ESP32-C3 ADC route) is withdrawn before it ever reached hardware: no
    module was flashed with it. This restores design v3's original channel
    map, CH1 = Battery A and CH2 = Battery B, and removes the open pin
    conflict item 26 carried (its provisional pin was D0, which is LoRa
    MISO). Battery B therefore has a real current reading again
    (bat_b_ma), and TESTS.md test 6 goes back to measuring draw from it
    instead of externally.

    The substantive new finding, and the reason this is a rule 5 entry
    rather than a plain revert: BOTH battery channels are BIDIRECTIONAL,
    because both packs are charged as well as discharged. The INA3221
    shunt register is signed, so a pack on charge genuinely reads a
    NEGATIVE current. Consequences now implemented fleet-wide:

    - Sign convention, published by the firmware and read by every app:
      positive = discharging, negative = charging, near zero = idle.
    - The firmware sign-extends the 13-bit two's complement value
      EXPLICITLY (ina13Bit in firmware/aux1/src/main.cpp) instead of
      relying on ">>" of a negative signed value, which is
      implementation-defined before C++20. Verified against the datasheet
      by a host-compiled unit test of the boundary cases (+/-1 count,
      full-scale both ways, a 500 mA charge).
    - Per-channel BATT_A_SHUNT_INVERT / BATT_B_SHUNT_INVERT flags handle a
      shunt soldered the other way round, so a wiring orientation mistake
      is a one-line firmware change, not a re-solder.
    - Classification lives in ONE place, shared_dart (batteryFlowFor,
      kBatteryIdleMa = 5 mA), with a deadband: the INA3221 resolves 0.4 mA
      per count, so a resting line jitters either side of zero and would
      otherwise flap between "charging" and "discharging" on noise alone.
    - The GCC shows direction as a word plus an icon (Nodes, Live Ops),
      never a bare negative number, which an operator would read as a
      fault when it is in fact good news.

    This also answers an open item from file 03's power note, which asked
    for Battery B's charge current to be measured on the bench: design v3
    has Battery B charging from the Pi USB in NORMAL mode and taking over
    in FALLBACK, so its expected reading is NEGATIVE (charging) while the
    Pi is alive and POSITIVE (discharging) once the Pi is dead. That was
    unmeasurable under item 26 (an ADC gives no current) and is now read
    straight from bat_b_ma; the per-mode expectation is tabulated in
    TESTS.md, where a positive reading with the Pi alive means the pack is
    not charging at all.

    Measurement limits now stated with the readings (datasheet plus the
    0.100 ohm shunt, confidence High): range +/-1638 mA, and beyond that
    the channel CLIPS rather than wrapping; resolution 0.4 mA per count.
    No wire-format, schema, or backend change: the beacon and JSON field
    layout are untouched, the node_health columns are REAL and already
    store negatives, and the Pi bridge parses with float(), so a signed
    value flows end to end with no Pi-side change.

## 2026-07-28 Stale DEGRADED nodes, and peers that carry position (rule 5)

31. Two field-reported bugs, one root cause between them: the fleet had no
    way to say a node had RECOVERED.

    BUG 1, a healthy drone stuck as DEGRADED. Connected to DRONE_A, the GCC
    showed DRONE_B down while B was working normally and actively syncing.
    Two independent faults combined:

    - Firmware: FALLBACK was terminal per boot (design v3, chosen for
      simplicity). The aux declares the Pi dead after 15 s of silence, which
      an ordinary `systemctl restart rescue-mesh-auxbridge` can exceed, and
      then beaconed over LoRa every 30 s FOREVER and stayed BLE-dark until
      hand power-cycled. So a service restart could permanently mark a
      healthy drone as down and hide it from the emergency app. Fixed: the
      module returns to NORMAL after FALLBACK_RECOVERY_PINGS (3) consecutive
      pings, restarts BLE, resumes the sensor feed, and sends fallback_exit.
      Entering takes 15 s of silence and leaving takes 15 s of contact, so
      the transition is symmetric and a flapping Pi cannot make it
      oscillate. Verified by a host-compiled state-machine test covering the
      restart case, a genuinely dead Pi, and the flapping case.
    - Backend: /health read the stored degraded flag back with no expiry and
      nothing anywhere ever wrote degraded=0, so one beacon heard once was
      permanent. Fixed: degraded is now DERIVED. A node is reported degraded
      only if its fallback beacon is newer than FALLBACK_EXPIRY (120 s, four
      beacon intervals) AND it is not currently an alive DTN peer. The
      rationale is evidential: a LoRa fallback beacon is one device (the aux
      module) CLAIMING its Pi is dead, while a DTN beacon is signed with
      K_SYNC and sent BY that Pi, so it is direct proof of liveness and must
      win. "Out of range" is also not "down", so a stale claim expires
      rather than persisting.

    BUG 2, peers showed only a last-seen time. The DTN beacon deliberately
    carries no position or battery, so the Nodes tab had nothing to show.
    Rather than extend the signed beacon payload (which would have forced
    every node in the fleet to update simultaneously or have its beacons
    rejected as forged), each node now FETCHES a peer's own /health over the
    existing fleet-CA-pinned sync channel and caches it in node_health.
    Peers therefore carry position, GPS fix, both batteries and uptime, each
    stamped with the FETCHING node's clock and surfaced as a separate "info
    age" column: a peer can be beaconing right now while its cached position
    is minutes old, and the UI must not conflate the two. A peer on older
    code simply fails the fetch and is listed with empty health instead of
    disappearing, so a partially updated fleet stays safe.

    That fetch also closes the loop on bug 1: reaching a peer's /health over
    HTTP is proof its Pi is alive, so the cached row is written with
    degraded=0 and overwrites any stale claim. node_health remains NOT
    replicated (it is live state, never a DTN record); it is fetched, never
    synced, so stale health never travels the mesh pretending to be current.

    Housekeeping forced by the above: node_health is append-only and now has
    a second writer (every peer, every sync cycle), so save_node_health
    prunes to the newest NODE_HEALTH_KEEP_ROWS (50) rows per node. Only the
    newest is ever read; the tail is kept for debugging. Without this the
    table would grow without limit on the SD card.

    No schema or wire-format change. Backend suite 35 tests (7 new).

## 2026-07-30 GCC internet detection, and garbled flight-controller messages

32. The GCC never knew whether it had internet. There was no connectivity
    code at all: the only way the app discovered the truth was by failing a
    request, so joining a Wi-Fi with real internet changed nothing visible
    and the online-only features (unit spec lookup, AI advisor) gave no
    useful signal beforehand. New services/connectivity.dart probes it
    properly and the nav rail now shows node status and internet status as
    two separate rows, because they are unrelated facts: at a deployment
    the correct state is node connected and internet absent.

    Method, and why not ping: ICMP needs raw sockets (root) and Dart has no
    ICMP client, so "ping google" is not available to us. The substitute is
    the standard captive-portal probe, an HTTP GET of a URL whose only job
    is to answer 204 No Content. A 204 with an empty body means real
    internet; any other reply means something answered but is not the
    internet, which is a captive portal and exactly what a drone AP looks
    like, so that state is named rather than reported as "offline"; no
    reply means offline. Three providers (Google, Cloudflare, gstatic) are
    raced so one blocked provider cannot produce a false negative, all
    time-boxed to 4 s and repeated every 30 s. Endpoints that signal
    success as "200 plus a magic body" (Apple, Microsoft) are deliberately
    NOT used: a portal also answers 200, so telling them apart means
    trusting body text and a wrong guess reports the field as online.
    Plain HTTP on purpose, since a portal can only be detected by letting
    it intercept; nothing sensitive is sent.

    Separately, the macOS build was missing com.apple.security.network.
    client in both entitlement files, which blocks ALL outbound connections
    under the sandbox. Fixed, but note this was NOT the cause of the
    reported symptom: the GCC is a Windows delivery (docs/RELEASES.md) and
    Windows has no sandbox entitlements, so on the tested platform the
    cause was simply the total absence of detection code.

33. Flight controller messages were displayed as garbled fragments, e.g. an
    orphaned "(xy diff:110 > 100)" with no indication of which arming check
    it belonged to. Cause: the MAVLink STATUSTEXT text field is 50
    characters, and ArduPilot splits anything longer into several messages
    sharing one id and numbered by chunk_seq, with a null terminating the
    last. The GCC ignored both extension fields and emitted every chunk as
    its own log line. It now reassembles them (mav_service.dart), keyed by
    id and ordered by chunk_seq so out-of-order UDP delivery still joins
    correctly, emitting only once the run from chunk 0 to the terminating
    chunk is complete. A 3 s timeout flushes a partial message rather than
    swallowing an arming failure whose tail never arrived. Four new tests.

    The messages themselves were real and are FC-side configuration, not
    app bugs: PreArm battery failsafe, logging failed, and compass field
    checks all block arming until resolved on the flight controller.

## 2026-08-02 Emergency-first UX pass, from tester feedback

34. The captive portal was built as a form, not as something a frightened
    person uses. It REQUIRED free text before anyone could ask for help,
    and it hid the most useful field of all, their location, behind a
    button most people never pressed. Rebuilt: tappable options (urgent
    ones first, since people skim the top), nothing required to be typed,
    location requested automatically and opt-OUT rather than opt-in, 17px
    base type with 60px tap targets, a GPS failure path that asks for a
    landmark instead of dead-ending, and a confirmation that is honest
    about delay-tolerant delivery so slowness does not read as being
    ignored. It never implies a rescuer is coming, because at that moment
    nobody has seen the message.

    Options come from a versioned per-mission config the GCC pushes to
    each node (mission_config.py). A node never pushed to serves a stock
    NEED-based list, so it is less tailored but never wrong. /health
    reports the version and whether it is stock or pushed, so partial
    rollout is visible before deploying rather than discovered later.
    Versions only move forward. The option LABEL text is embedded in the
    message content, so changing the config later never orphans older
    messages.

    Not shipped: the "let people nearby see I need help" consent
    checkbox. The feature it gates does not exist yet and an inert consent
    control in an emergency app misleads the user. It ships with the
    feature.

35. Three GCC usability faults behind "the AI does not work, I don't know
    why" and "the UI is not straightforward":

    - AI failures were reported in a SnackBar: four seconds, bottom of
      the screen, truncated. The reason WAS being given, invisibly. Now a
      dialog that must be dismissed, and it names the likely cause
      (offline, empty model name, 401, 429, 404) rather than only echoing
      the raw error.
    - The map had no MapController at all, so the camera was set once from
      initialCenter and then frozen: drawing an operation area left the
      operator looking wherever the map happened to open. It now frames
      the area when it first appears or is redrawn, with a button to
      return there, and does not fight the operator while they pan.
    - The drone-found notification in the emergency app fired on EVERY
      matching BLE advertisement, and the aux module advertises every 0.5
      to 1 s, so standing near a drone produced several high-priority
      alerts per second. Rate limited per node to one per five minutes,
      while the sighting itself still reaches the UI on every hit.

    Position on sharing locations between victims, after discussion: in
    Sri Lankan floods people already post their location publicly on
    social media to seek help, which is real evidence of what users
    actually want and outweighs abstract privacy reasoning. Peer
    visibility will therefore be built, gated on explicit disclosure and
    an opt-in at the moment of sending. Two things stay true regardless:
    the mesh cannot un-share (store-and-forward has no recall, unlike
    deleting a post), so the choice must be deliberate; and RESCUER
    positions are not the victim's consent to give, so they remain
    distance-and-direction unless HQ configures otherwise.

36. The victim-portal config version counter is REMOVED, superseding the
    counter described in item 34. Reviewing it surfaced the real problem:
    the counter itself was the defect, not the places it was stored.

    A counter has to live somewhere and be kept correct, and whoever holds
    it can legitimately be wrong. A fresh GCC install, a second operator's
    laptop, or cleared settings all rewind it, and the operator then gets
    pushes rejected with no visible cause. Two rounds of fixes (moving it
    from the mission file to prefs, then reconciling it against the node
    with max(local, remote) + 1) each made it more robust while leaving the
    underlying complexity in place.

    A config now identifies itself by a SHA-256 fingerprint of its own
    visible content, and ordering comes from updated_at. That gives both
    things the counter was approximating, and gives them exactly:

    - Comparing nodes is now content equality, not numeric ordering. Same
      config_id means the same options, whoever pushed them and in whatever
      order. The GCC computes the fingerprint locally and can say "this
      node already matches" without pushing anything, so the Nodes chip
      reads "matches this mission", "different options", or "stock".
    - A stale push is refused because its timestamp is older, with an
      explicit force override for the case where a laptop clock was wrong.
      Re-pushing identical options is harmless and produces the same id.

    Nothing stores a counter now: not the mission file, not prefs, not the
    node. The fingerprint is a cross-language contract between Dart and
    Python, so a test pins the Dart output against the value the node's own
    content_id() produces; if they ever diverge the GCC would silently
    report every node as mismatched forever.

    Credit where due: the operator spotted that the max() reconciliation
    was a symptom rather than a cure.

37. Victim conversations: replies, and a device-scoped read on the victim
    plane. This REVERSES file 09's rule that the open victim plane carries
    no read endpoints, deliberately and with the reasoning recorded.

    Why reverse it: the emergency app is the VICTIM's app, and a victim who
    has asked for help cannot tell whether anyone received it. Testers
    asked for the familiar messaging idiom, where a tick means delivered
    and a second tick means seen, because it has zero learning curve at the
    worst moment of someone's life.

    New replicated table message_replies (signed with K_MSG, append-only on
    ingest, synced like every other record) so a reply written at one node
    reaches whichever drone the victim next meets, not just the node the
    rescuer happened to stand beside. POST /messages/{id}/reply is
    authenticated-plane, rescue or HQ only.

    The read, GET /my-conversation/{device_id}, keeps the property the
    original rule protected rather than abandoning it. The only key is the
    caller's own 122-bit random device id; there is no listing endpoint, no
    search, and no path from one id to another. An unknown id returns an
    empty thread identical to a real but silent device, so it cannot be
    used as an oracle. Tests assert the cross-device isolation and the
    absence of enumeration, not just the happy path.

    Residual risk, stated rather than buried: the victim plane is plaintext
    by design (file 09 F3), so someone sniffing the same AP could capture a
    device id in flight and read that thread. That is the same exposure the
    message CONTENT already has on this plane, so it is not a new class of
    risk, but it is real and belongs in the thesis.

    Tick semantics are deliberately honest about a delay-tolerant network,
    which is where the familiar idiom would otherwise mislead. WhatsApp's
    ticks imply seconds; ours can mean hours. So there are THREE states,
    including one WhatsApp does not have: waiting on the phone with no
    drone in range, stored on a drone, and seen by a rescuer (the existing
    CLAIMED status). Without the first state a victim with no drone
    overhead sees nothing happening and concludes they were ignored, when
    the system is working exactly as designed. "Seen" never implies anyone
    is on the way, because at that moment nobody is.

38. Victim map, and victims visible to each other. Recorded as a decision
    rather than a default, because it trades privacy for reach.

    The operator's argument, which changed the design: in Sri Lankan floods
    people already post their location publicly on social media to seek
    help, and in most disasters neighbours pull people out long before
    responders arrive. That is evidence about what people in this context
    actually want, and it outweighs abstract privacy reasoning. A system
    that hid survivors from each other would discard the mutual-aid benefit
    and push people back to social media, which reaches a larger and far
    less relevant audience than the few hundred metres around a drone.

    Rescuer positions are included too. Responders here are typically army,
    publicly deployed and announced, so the operator judged their positions
    appropriate to share. It remains a mission-config flag, since that is
    the organisation's call rather than any individual victim's.

    What the decision explicitly does NOT extend to, and the tests enforce:
    the feed carries POSITIONS ONLY. No message content, no device ids. A
    person reading the map learns that someone nearby needs help and
    whether anyone has picked it up; they cannot read that person's medical
    details, and they cannot link two positions to the same individual over
    time. That keeps the whole stated benefit and drops most of the harm.

    Also noted honestly: the mesh cannot un-share. Store-and-forward has no
    recall, unlike deleting a social media post, so what is published stays
    published. The operator accepted this.

    The victim map ships no tiles, like the rescue app map: markers on a
    plain background, since there is no internet at a site. It shows the
    distance to the nearest rescue team, which is the single most
    reassuring number available.

39. A latent defect in the sync loop, found while chasing a field problem
    that turned out to be unrelated (item 40). Recorded honestly: this was
    NOT the cause of anything observed in the field.

    The peer-health cache added in item 31 ran BEFORE the per-table sync
    loop and was called with no guard. Its internal try covered only the
    HTTP request and caught only RequestException, JSONDecodeError and
    ValueError; the database write sat outside it, and a missing CA file
    raises OSError rather than a RequestException. Anything escaping would
    have propagated to sync_with_peer, then to sync_loop's catch-all,
    aborting the entire cycle for every peer and every table. So a
    convenience feature was one exception away from silently stopping
    victims' messages crossing the mesh.

    Fixed in three layers: fetch_peer_health catches Exception around both
    the request and the store; the call site guards it too, since it reads
    the peer dict before its first try and runs ahead of the loop; and each
    table's sync catches Exception, so a sqlite error mid-ingest is
    isolated rather than taking the remaining tables down.

    The rule now written into the code: replicating a victim's message is
    the product, and everything else, health caching included, is optional
    and must fail quietly. 5 tests enforce it.

    Also fixed while here: the test suite shares one process and therefore
    one rate-limit budget, so a module that posts a lot left later modules
    getting 429s and failing for unrelated reasons. An autouse fixture
    resets the limiters per test.

## 2026-08-02 Field finding: USB power, not software (rule 5)

40. Two nodes stopped syncing during field testing. The investigated cause
    was NOT software: DRONE_B's AR9271 had disappeared from the operating
    system entirely (`iw dev wlan1 info` returning ENODEV, no such device),
    so there was no interface to form the IBSS cell with, dtn-net could not
    start, and the nodes silently diverged. Every downstream symptom
    followed from that single fact, including "the whole message list
    changes when I switch nodes", which was simply the two databases having
    drifted apart while the link was down.

    Root cause: insufficient USB power. Running the Pi from batteries could
    not sustain the AR9271 (roughly 400 to 500 mA) alongside the aux module
    on the same USB budget; the adapter browned out and dropped off the bus
    after running for a while. Swapping to a phone charger fixed it
    immediately and completely.

    Consequences worth carrying into the design and the thesis:

    - The battery arrangement as tested CANNOT reliably power a node. Any
      figure that assumes it can is optimistic. A node needs a 3 A class
      supply, or the AR9271 needs a powered hub. Confidence: High, it
      reproduced and the fix was decisive.
    - The failure is SILENT from the application's point of view. Sync kept
      logging SYNC_OK with imported=0, which reads as healthy, because a
      node with no peers has nothing to import and cannot tell the
      difference between "nobody has anything new" and "I cannot see
      anybody". The GCC does show peers as empty, which is the honest
      signal, but nothing raises an alarm.
    - Diagnostic order that actually worked, now in the runbook: check
      whether the INTERFACE EXISTS before investigating sync logic. Two
      plausible software theories (a regression in the health cache, then a
      clock jump moving the sync cursor past the data) were both disproved
      by the node's own logs and cursor values before the missing interface
      was found.

41. **Rescuer sign-in became a single scan, and the PIN moved inside the QR
    (field backlog #17).** What testers hit: a rescuer could only be issued
    credentials while standing at the same drone as the GCC, because the
    personnel record lived only on the node that minted it and reached
    other nodes at DTN sync speed, which may be never if the link is down.

    The fix has two halves. The record travels with the RESCUER: the GCC
    prints their K_MSG-signed personnel record into a QR, the phone hands
    it to whichever drone it is joined to via `POST /enrol`, and that node
    verifies it through the same `ingest_personnel` path sync itself uses.
    A forged record is rejected exactly as a forged sync record would be,
    so nothing is trusted merely because a phone presented it.

    The second half is a posture change and is recorded here because it
    weakens something deliberately. The QR carries the PIN as well as the
    record, so signing in is one scan and no typing. That is only
    defensible because credentials are scoped to a mission: activating a
    different mission in the GCC retires every credential issued under the
    previous one. The operator asked for this explicitly after seeing the
    scan-then-type flow, on the grounds that a rescuer in gloves and rain
    will not type a six-digit PIN reliably.

    What that costs, stated plainly rather than buried: anyone who
    photographs the QR while it is on screen has that rescuer's full
    credentials until the mission ends. The mitigations are the mission
    scope, a warning in the issue dialog telling the operator not to leave
    the code displayed, and the PIN path being kept as the fallback.
    Confidence: High on the mechanism, Moderate on whether mission scoping
    is tight enough in practice, since it depends on operators actually
    switching missions between deployments.

42. **The victim app's SOS screen now offers the same tappable options as
    the captive portal (field backlog #11).** It previously had one empty
    text box. Every objection the testers raised about the old portal
    applied to it just as hard: wet hands, a cracked screen, a keyboard in
    the wrong language, and panic all make typing the one thing a victim
    cannot reliably do.

    The options are FETCHED FROM THE NODE (`GET /portal-options` on the
    public plane), not hardcoded in the app. That is the part worth
    keeping: the operator may edit the option list per mission, and if the
    app carried its own copy then a victim with the app and a victim with a
    browser would report different vocabularies, making the rescue team's
    tally meaningless. The app ships the stock list only as a fallback for
    a node running older code, and stock is deliberately need-based rather
    than disaster-specific, so it is never wrong, only less tailored.

    Location is now opt OUT rather than attached silently. The switch is on
    by default because a team that knows only that somebody needs help
    cannot act on it, and the confirmation screen says plainly which of the
    two situations they are in. Sending with nothing selected is still
    allowed: an SOS with no detail still says a person is here, which is
    worth more than forcing them to tick a box first.

43. **Degraded drones got their own tab, a replicated LoRa log, blinking
    map markers and map layer filters (field backlog #13).** Until now a
    drone on LoRa fallback produced one red banner and a static red marker
    on a map already carrying victims, checkins, rescuers, placements and
    deployed drones. The operator's objection was that they could not find
    it, and could not answer the question that actually matters when
    deciding whether to walk out to a drone: what has it been telling us
    since it went down.

    A new `lora_events` table records every frame a node hears, with RSSI,
    SNR, the position and battery the beacon carried, and the last victim
    message that node was still holding. Three design points worth stating:

    - **It replicates, unlike `node_health`.** The node that hears a
      beacon is whichever one is nearest the failure, and HQ may be joined
      to a different one. A log that exists only on the node nobody is
      looking at is not a log.
    - **The row id is derived from the frame content plus which node heard
      it**, not a random uuid, so a frame replicated back to a node that
      already has it collides on the primary key instead of appearing
      twice. Two DIFFERENT receivers still produce two rows on purpose:
      two independent receptions are better evidence than one, and the tab
      shows "heard by" for exactly that reason.
    - **It is pruned** every twentieth sync cycle, keeping 2000 rows. A
      node down for a day beacons roughly 2900 times (one per 30 s), and
      every healthy node in earshot keeps a copy.

    The map markers now blink rather than sitting still, because
    peripheral vision detects change far better than colour, and they stop
    on their own when the node stops being reported as degraded (nothing
    has to be told to stop, which is the bug that shape avoids). Map layer
    filters were added alongside, defaulting to everything visible, with
    the button showing how many layers are HIDDEN rather than how many are
    shown: a filter someone forgot they set is how a victim goes unseen.

    Recovery is shown rather than silently dropped. A node that came back
    on its own stays listed under "Recovered" for an hour, because "it
    fixed itself" is something the operator acts on by not walking out
    there.

44. **The GCC composer can attach objects with an @ picker (field backlog
    #14).** Typing `@` in an announcement body opens a picker of degraded
    drones, drones, victims and rescuers; choosing one writes its id AND
    its coordinates into the text.

    The problem was never typing speed. "The drone in the north is down, go
    to the victim near the school" is ambiguous to everyone who reads it,
    and the operator had no way to name things as the system names them
    without reading ids off another tab and copying them by hand.

    Kept as PLAIN TEXT deliberately. Announcements already replicate as
    text and render as text in the rescue app, so a structured attachment
    format would have meant changing the wire contract, migrating every
    node, and leaving older app installs showing an empty message. A line
    like `@DRONE_B (6.92710, 79.86120)` needs none of that and stays
    readable in a log file.

    Ordering in the picker is the operator's priority order rather than
    alphabetical: degraded drones first, then UNCLAIMED victims, then
    everything else, because the first screenful is all most people read
    mid sentence. A victim with no reported position still attaches, with
    no coordinates rather than invented ones.

    Two implementation notes that came out of testing rather than design.
    The text surgery is a separate pure function because an off-by-one
    there silently eats a character from a sentence somebody is composing
    under pressure, and the first version left a double space when
    attaching mid sentence. The picker triggers only on a single typed
    character, never on a paste containing an @, so it cannot jump out
    unpredictably.

45. **The operator can now place the GCC and draw what they intend (field
    backlog #4).** Three additions to the planning map: a single tap places
    the ground control centre, two taps draw an arrow for the direction the
    operation is expected to advance, and a tap plus a radius circles an
    area they suspect needs attention. All three save with the mission and
    all three are fed to the AI advisor.

    Why it matters more than it looks: the map says where the disaster is,
    and that is all it says. Which way the teams are moving through it, and
    which corners the operator is worried about, exist nowhere in the
    system and cannot be inferred from a polygon. The advisor was being
    asked to plan without the one input only a human has. The prompt now
    labels each piece for what it is, including telling the model that
    suspected areas are hunches to be weighted BELOW the area polygon
    rather than treated as confirmed reports.

    The GCC position is operator-supplied because nothing can know it: the
    GCC is a laptop in a tent with no GPS.

    Two interaction decisions worth recording. Drawing is now an explicit
    mode (area, GCC, arrow, suspected, or none) with a line of text saying
    what the next tap will do, because a map where a tap can mean five
    things is a map that gets used by accident. And switching tools
    discards a half-drawn arrow, so a dangling start point cannot attach
    itself to an unrelated tap later.

    Compatibility: mission files saved before this load unchanged, with the
    fields simply absent. Covered by a test, because every mission file the
    operator already has is one of those.

46. **Node cards, and an empty state that does not mislead (field backlog
    #6 and #10).** The peers table was reported as never showing peers. It
    was correct: there were none, because DRONE_B's USB WiFi adapter had
    browned out (item 40). The presentation was still part of the problem,
    and that is what changed.

    The old empty state said "no peers in beacon range", which is
    indistinguishable between the normal delay-tolerant case and a dead
    adapter. It now names both possibilities and gives the one command
    that separates them, because an evening was spent on the wrong theory
    for want of that sentence. Peers became cards with a drawn quadcopter
    rather than table rows, showing the beacon age and the details age
    SEPARATELY, since a peer can be beaconing right now while its position
    and battery are minutes old.

    The drone picture is drawn in code rather than shipped as a photo.
    There is no internet at a deployment so any image must live in the
    binary, and a photo in the binary is a photo of SOME drone, which
    becomes misleading the moment a volunteer arrives with a different
    airframe. The colour carries state, so the picture is not decoration.

    On #10, auto-open: no defect found. The path is wired correctly and
    now has tests driving the same callback the radio drives. The likely
    explanation for the report is #12: the watch toggle did not work until
    Bluetooth was cycled, so no scan ran, so no sighting ever arrived. A
    feature that is never reached looks identical to a broken one.

47. **Mission planning reordered around the area, with card resources and
    an honest AI progress display (field backlog #3, #3b, #3c).**

    **Area first.** The operation area was reachable only from the map, so
    an operator working down the Mission tab inventoried drones before
    deciding where they were going. It is now the first step, drawing it
    takes them to the map with the tool already on, and the map frames
    itself on the result. The tab is numbered because it genuinely is a
    sequence: where, then what you have, then the plan.

    **The area is no longer permanently shaded.** The wash of colour stays
    while planning and drops to a thin outline once the mission is
    running, where it was making every marker underneath harder to read
    and telling the operator something they already knew.

    **Resources became cards and draggable chips.** Drones are cards with
    a drawn quadcopter that dims when specs are unknown; spare modules are
    chips that drag onto a drone to attach. A module already fitted is not
    draggable, which matches both the physical act and the rule from item
    #2 that a module cannot be on two airframes. The dropdown in the add
    dialog stays, because drag-and-drop with a trackpad in a hurry is not
    something anyone should be forced into.

    **#3c is a safety property, not a preference.** An unapproved plan
    drawn on the operations map is indistinguishable from a decision, and
    this proposal comes from a language model that has never seen the
    ground. Drafts now show while planning and nowhere else, and they
    BLINK until approved. Covered by tests on the visibility rule itself,
    including that withdrawing approval actually withdraws it.

    **On the AI progress display, stated plainly for the thesis:** reading
    the mission, asking the model and checking the plan are real work.
    "Placing on the map" is a reveal of an answer that arrived complete,
    presented one placement at a time so the operator can watch where each
    lands. Nothing in the UI claims the model is thinking step by step,
    because it is not, and a progress display that invents activity would
    be worse than a spinner.

48. **The front panel switch must cut BOTH batteries, and the Pi now says
    goodbye before it halts (field backlog #1, correcting the first
    version of that work).** The panel guide originally said to wire the
    power switch into the Raspberry Pi's supply. The operator spotted the
    consequence before anything was soldered.

    The two sub-units have separate batteries deliberately: that is the
    whole fault-tolerance design. Cutting the Pi's supply alone leaves the
    aux module running, missing heartbeats, and concluding the Pi has
    crashed, so it starts transmitting LoRa fallback beacons announcing a
    node failure. A deliberate power-off was indistinguishable from a
    crash, and the fleet would raise an alarm for a drone somebody simply
    switched off.

    Two changes, because the hardware fix alone is not enough:

    - **A DPST switch** cutting both battery positives on one lever, so
      both sub-units die together and the aux module never gets the chance
      to reach a wrong conclusion.
    - **A planned-shutdown notice.** The recommended power-down is still a
      clean shutdown first, to protect the SD card, and during that halt
      the Pi is down while the aux module is powered: the same trap. The
      aux bridge now sends `{"type":"shutdown"}` on SIGTERM, which systemd
      raises both on `systemctl stop` and on a full halt, and the module
      suppresses fallback for five minutes.

    The grace window is bounded rather than indefinite, and that is the
    part worth defending. An unbounded flag would mean one stray message
    could silently disable the fallback beacon for the rest of a flight,
    and the beacon is the only thing that module exists to do. Five
    minutes covers a clean halt plus somebody walking to the switch; after
    it expires the module behaves normally, so a node accidentally left
    powered still reports itself.

    Verified without hardware by `tools/aux_shutdown_notice_test.py`,
    which runs the real bridge against a pty, sends SIGTERM the way
    systemd does, and asserts the module was told. Requires reflashing
    both aux modules; without it a clean shutdown still produces one
    spurious alert that the fleet clears itself.

49. **Adapters can be moved between nodes without breaking the mesh
    (`DTN_MAC_ALT`).** The fleet has three nodes and two AR9271 adapters,
    so adapters get swapped. Each node pins its adapter to the name
    `wlan1` by MAC through a systemd `.link` file, so a moved adapter came
    up under a kernel-assigned name instead: `dtn-net` then found no
    `wlan1`, the cell never formed, and from a laptop it looked exactly
    like a sync bug. That is the same failure signature that already cost
    an evening (item 40).

    `systemd.link` accepts a whitespace-separated MAC list, so the node
    conf gained an optional `DTN_MAC_ALT`. Listing every adapter the fleet
    owns on every node makes them physically interchangeable with no
    reconfiguration.

50. **dtn-net follows the interface instead of running once at boot.**
    Reported from the field while following the node update runbook: the
    USB WiFi adapter was not detected unless the whole board was
    rebooted, and the runbook's sync gate returned nothing.

    Both symptoms were the same defect. `dtn-net.service` was a
    `Type=oneshot` unit wanted by `multi-user.target`, so it ran once,
    five seconds after boot. With no adapter present at that moment the
    bring-up script failed, systemd retried, hit its start limit, and gave
    up permanently. Plugging the adapter in afterwards re-ran nothing, so
    the node had no IBSS cell, no peers, and therefore no sync log lines
    at all.

    It is now `BindsTo` and `WantedBy` the `wlan1` device unit, so it
    starts when the adapter appears and stops when it is removed. Hotplug
    works, and so does moving an adapter between nodes, which matters
    because the fleet has fewer adapters than nodes (item 49).

    Two things worth carrying forward from how this was diagnosed:

    - **The gate command in the runbook was not diagnostic.** Grepping the
      sync log for a table name returns blank both when the table is not
      registered and when the loop never ran for want of peers. Those are
      completely different problems and only one is a code bug. The
      runbook now has a four-step ladder that separates them, and it
      states which cause is the common one.
    - **This is the third time an absent `wlan1` has presented as a sync
      problem** (items 40 and 49 being the others). The interface existing
      is now the first thing every relevant runbook tells you to check.

51. **`tests/test_sync_wiring.py`: a replicated table must be registered
    everywhere or fail here.** Adding one means touching five places
    (`REPLICATED_TABLES`, `_PAYLOAD_FN`, `SYNC_PATHS`, `INGEST_FN`, and a
    route). Miss one and the symptom is silence in the sync log, which is
    the worst thing to debug remotely, as item 50 showed.

    Seven tests now assert every table has a payload function, a sync
    path, an ingest function, a route actually served by the API, a
    CREATE TABLE, and no orphaned paths. One more asserts the count is 8,
    so adding a table forces a look at the documents that quote that
    number.

52. **Setup no longer refuses to run on a node whose adapter is elsewhere,
    and `dtn_doctor.sh` diagnoses the whole mesh chain in one command.**
    Both came straight out of a field session.

    `setup_node.sh` hard-failed with "could not determine both MACs" on a
    node with no USB adapter plugged in. With three nodes and two
    adapters, one node always lacks one, so the script could not be run
    on the node that most needed it. The MAC is only needed as a value to
    write into a `.link` file; the hardware does not have to be present.
    The error now says that, and walks through reading the MAC off
    whichever node currently holds an adapter and filling in `DTN_MAC`
    and `DTN_MAC_ALT`.

    `systemctl enable dtn-net` also became `reenable`, because item 50
    changed that unit's `[Install]` section and plain `enable` leaves the
    old `multi-user.target` symlink in place alongside the new one.

    **`tools/dtn_doctor.sh`** exists because an absent or misconfigured
    `wlan1` has now presented as a "sync problem" three times (items 40,
    49, 50). It checks every link from "is the adapter on the USB bus" to
    "are we actually syncing", stops at the first break, and prints the
    exact fix. It changes nothing itself.

    The check that would have saved this session outright: **interface
    mode**. On the node in question `wlan1` existed with the right name
    but was `type managed`, not `IBSS`, which means nothing had ever
    configured it. That is invisible in `ip link` output and is the state
    a node sits in after an adapter is plugged into an already-running
    board.

53. **wlan1 is matched by DRIVER, not by MAC address. Item 49 was the
    wrong fix.** Field report: after a reboot the interface names swap.
    The onboard radio was fine; the USB adapter was the problem.

    MAC pinning assumes every adapter has a stable, unique hardware
    address. Cheap AR9271 dongles do not: some carry a duplicated default
    address, and some present a different one after a power cycle. Pin a
    name to an address that changes and the interface comes up unnamed,
    which is exactly the reported symptom.

    Both `.link` files now match on what is actually invariant. The Pi's
    built-in radio keeps its MAC match, because it is soldered on and its
    address genuinely never changes. The USB adapter matches
    `Driver=ath9k_htc`, which is true of every AR9271 and of nothing else
    in the node.

    Three problems close at once:

    - Reboots cannot rename the interface, because the driver does not
      change.
    - Adapters became interchangeable with no configuration at all, which
      supersedes `DTN_MAC_ALT` from item 49. That variable is now unused
      and kept only as a record.
    - `setup_node.sh` no longer needs the adapter present or its MAC
      known, so a node whose adapter is currently in another node can
      still be set up.

    The lesson worth keeping: item 49 fixed the symptom by adding a second
    MAC to match. It took a second field report to ask why the identifier
    was unstable in the first place. Match on the property that cannot
    change, not on the one that happened to work.

54. **`dtn_doctor.sh` told a node with a plugged-in adapter that no
    adapter was visible.** The first version printed "AR9271 seen on the
    USB bus" and then, two lines later, "No USB WiFi adapter is visible to
    the kernel at all". Both from the same run.

    The gap was a real diagnostic case the script did not handle: the USB
    device enumerates but the driver never creates a network interface,
    which is what missing `ath9k_htc` firmware looks like. It now detects
    that case specifically, prints the relevant `dmesg` lines, checks
    whether `/lib/firmware/htc_9271.fw` exists, and gives either the
    install command or a module-reload plus the brownout warning.

    Verified by stubbing the exact node state that produced the
    contradiction.

55. **`dtn_doctor.sh` now separates "no adapter was ever here" from "the
    adapter was working and vanished", and installs as `dtn-doctor`.**
    Both came from the same field session as items 53 and 54.

    The two states look identical at the moment you look: no device in
    `lsusb`, no `wlan1`. They have completely different causes. Nothing
    ever enumerated usually means the adapter is physically in another
    node, which is routine when the fleet has fewer adapters than nodes.
    An adapter that enumerated earlier this boot and then disappeared is
    the USB brownout from item 40, and it is a power fault rather than
    anything to do with software.

    The script now reads `dmesg` for evidence of `ath9k_htc` earlier in
    the boot, prints the USB disconnect lines when it finds them, and
    gives the appropriate fix for each case rather than one generic
    paragraph that covers both badly. It also dumps the full `lsusb` so
    the operator can see what IS on the bus.

    It is installed to `/usr/local/sbin/dtn-doctor` so it runs from any
    directory. The relative path caught the operator twice in one session,
    which is exactly the friction you do not want while diagnosing a node.

56. **The doctor gave a node a clean bill of health while its adapter was
    dropping off the bus every thirty seconds.** Field session on
    DRONE_B: every check passed and the script printed "No faults found
    in the mesh chain on this node". Meanwhile `dmesg` showed the AR9271
    had disconnected twice in the previous forty seconds, with the USB
    host controller reporting "Cannot enable. Maybe the USB cable is
    bad?" and "attempt power cycle" at boot.

    The flaw was structural, not a missed case. Every check asked "is
    this correct RIGHT NOW", and an adapter that flaps passes all of them
    in the gaps between drops. Silence about an unstable link is worse
    than not checking, because it actively tells the operator to look
    somewhere else.

    A stability check now counts USB disconnects and port-enable failures
    for the boot and reports them even when everything is currently up.
    Port-enable failures are called out as an ELECTRICAL fault
    specifically, with the fix ordered by likelihood: 3 A supply, then a
    powered hub, then port and cable, then swapping adapters to tell a
    dead adapter from a dead port. It also says plainly that range and
    sync measurements taken through a flapping adapter are void, because
    the mesh will vanish mid-test and the result will look like a
    software problem.

    One false alarm suppressed while there: `ath9k_htc` tries
    `htc_9271-1.4.0.fw` first and falls back to `htc_9271.fw`. The first
    attempt logs a scary "failed with error -2" that is entirely normal.
    The doctor now says so when the fallback succeeded, instead of
    leaving an alarming line for somebody to chase.

57. **One node procedure replaces five, and the drift that made it
    necessary.** The three nodes had ended up in different states because
    each was updated at a different time by a different runbook: DRONE_A
    naming its adapter by MAC, DRONE_B by driver, DRONE_S untouched this
    round. Every one of those worked in isolation, which is what made the
    inconsistency dangerous. It would have surfaced during a measurement,
    not before one.

    The underlying cause was documentation, not code. Five separate
    "update" runbooks had accumulated, one per round of changes, and there
    was no way to know which to follow or whether a node had had all of
    them. `setup_node.sh` has always been re-runnable and always brought a
    node to a known state, so those documents were describing a
    distinction that did not exist.

    `docs/node_reset.html` is now the only node procedure: pull, run the
    script, reboot, verify with `dtn-doctor`. It states what is preserved
    (the database, and the fleet master secret, which is read from
    `deploy/secrets/` rather than regenerated), what is reissued (the node
    TLS certificate, signed by the same CA, so nothing needs
    reconfiguring), and repeats the warning never to run
    `make_fleet_ca.sh` on a node.

    The five superseded runbooks moved to `deploy/archived_runbooks/`
    rather than being deleted, because they record what each round changed
    and in what order, which the report needs.
    `deploy/RUNBOOKS.md` indexes the eight that remain, with the rule that
    keeps the list short: updating a node and fixing a broken node are the
    same operation, so new runbooks are only for genuinely new things.

58. **The DRONE_B adapter fault is a single faulty USB port, not a power
    brownout. My earlier diagnosis was wrong.** The operator established
    it by testing directly rather than reasoning from logs: the adapter
    works in every other port on the same board, including replug, and
    fails in one specific port. On that port it enumerates at boot and
    then fails on every hot replug.

    That pattern is diagnostic. A hub powers all of its ports once during
    startup, which a marginal port can survive; a hot insert requires that
    port to perform its own powered reset, which it cannot. Hence "works
    at boot, dead on replug" for one port while the rest of the board is
    fine.

    Recording the mistake because it matters for how this project
    diagnoses things. I read `Cannot enable. Maybe the USB cable is bad?`
    plus `attempt power cycle` and matched it to item 40's brownout, which
    was a real failure on this hardware. That gave a plausible story that
    fitted the evidence I had, and I recommended a 3 A supply and a
    powered hub on the strength of it. The evidence I did not have was the
    other three ports, and one direct comparison settled what a lot of log
    reading had not. **The same error string has more than one cause, and
    the cheap experiment beats the confident inference.**

    `dtn_doctor.sh` now makes the distinction itself: it reports which USB
    path the adapter is on, collects which ports have reported enable
    failures, and if they are all on ONE port says so explicitly, with
    "move the adapter and label the bad port" rather than "buy a bigger
    supply". Failures spread across several ports still point at the
    supply. It also mentions `rpi-eeprom-update -a` as a cheap one-off,
    since the VL805 firmware handles port power and reset.

    No change to the item 40 finding: that was a different node under
    battery power and the fix there was decisive. Both faults are real and
    they are not the same fault.

59. **`dtn-doctor` was installed as a copy, so `git pull` did not update
    it.** The operator pulled the per-port diagnosis from item 58, ran
    `sudo dtn-doctor`, and got the previous version's answer. The new
    logic was correct and simply was not the code being executed.

    `setup_node.sh` used `install` to place the script at
    `/usr/local/sbin/dtn-doctor`, so the command kept running whatever
    version existed at the last setup run. For a diagnostic tool this is a
    particularly bad failure: it does not error, it confidently gives you
    a stale answer, and it cost a round of field debugging.

    It is now a symlink into the working tree, so the command is always
    the current file. The script also prints its own path and the git
    revision that last touched it, so a stale or unexpected copy is
    visible in the first three lines of output rather than inferred from
    missing sections.

    General point worth keeping: any tool installed by copying is a tool
    that will silently go stale. Anything that changes as often as a
    diagnostic script belongs on a symlink.

    Also softened a misleading count. The disconnect tally includes the
    operator's own unplug and replug testing, which during triage is most
    of it, so the script now says so on the same line.

60. **The doctor reported a solved problem as a live fault.** With the
    adapter moved to a working port, it still printed FAIL, because
    `dmesg` holds the whole boot and the errors from the abandoned port
    are still in it. Reporting history as a current fault is how a working
    node gets debugged for another hour, which is the opposite of the
    tool's job.

    It now compares the port the adapter is actually IN against the ports
    that have logged failures, and distinguishes three cases: the adapter
    sits in a failing port (a real fault, move it), the adapter has been
    moved out of one (history, say so and suggest labelling the bad port),
    or failures span several ports (the supply, not a port).

    Unknown current port defaults to "assume affected", so a case the
    script cannot resolve never reads as safe.

    The port logic was also three overlapping `if` blocks, which is why
    the OK branch fell through into a second FAIL. It is one `if/elif`
    chain now, and all three outcomes are tested by replaying stubbed node
    states.

61. **A node could be configured as a DIFFERENT node, and nothing
    noticed.** `setup_node.sh` takes the node letter purely as an
    argument. Running `setup_node.sh a` on drone-b configured drone-b as
    DRONE_A: node id DRONE_A, access point RESCUE_A, and DTN address
    10.99.0.1, which DRONE_A already holds.

    The failure this produces is unusually nasty. Two boards answer to one
    mesh address, so the cell cannot form and the peer list stays empty,
    while every other check on both nodes passes: the interface exists, it
    is in IBSS mode, it joined the right SSID, the services are running.
    The operator spotted it in a single log line reading `joined
    RESCUE_DTN @2437MHz as 10.99.0.1` on the wrong board.

    Two changes. `setup_node.sh` now refuses when the hostname follows the
    `drone-x` convention and disagrees with the requested letter, printing
    the command that was probably intended. It stays permissive when the
    hostname is something else, because a freshly imaged Pi has not been
    renamed yet and first-time setup must not be blocked.

    `dtn_doctor.sh` cross-checks hostname against the configured node id
    and DTN address, so a board that was mis-configured before the guard
    existed is caught rather than silently wrong. It also offers to clear
    the database, since records written under a borrowed identity carry
    the wrong originating node id.

    Worth noting for the report: this is the fourth distinct fault this
    week whose only symptom was an empty peer list. Missing firmware, a
    dead USB port, stale naming rules, and now a duplicated address all
    present identically from the application's point of view. That is a
    genuine observability finding about the system, not just a run of bad
    luck, and it is why the diagnostic script now checks the whole chain
    rather than any single link.
