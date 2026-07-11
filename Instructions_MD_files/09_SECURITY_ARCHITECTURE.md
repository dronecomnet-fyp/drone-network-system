# 09 SECURITY ARCHITECTURE: WHAT TO KEEP, WHAT TO FIX, WHAT TO DROP

Purpose: an honest review of the Phase 1 security implementations against a
realistic threat model, and the corrected target architecture for Phase 2.
This file is cross-cutting: its tasks are applied INSIDE work packages 01,
02, 04, 05, and 08, not as a separate build step. The thesis write-up should
mirror the structure here (threat model first, then controls), because
controls justified by a threat model read as engineering; controls without
one read as decoration.

## 1. Threat model (write this into the thesis before any control)

Assets, in priority order:
1. Integrity of victim messages and claims (a forged or altered rescue
   request misdirects rescuers; worst-case harm).
2. The drone control link (a hijacked MAVLink session crashes or steals the
   system drone; new asset introduced by file 08).
3. Personnel credentials and the fleet trust root (forged identity lets an
   attacker claim requests or publish announcements).
4. Availability of the nodes (spam/DoS on an open AP).
5. Confidentiality of victim messages (matters, but ranks below integrity
   and availability in a disaster: a readable plea for help that arrives
   beats an unreadable one).

Adversaries considered realistic:
- A1: a person near a node with a laptop or phone on the open AP.
- A2: someone who physically captures a landed or crashed drone.
- A3: a spammer flooding the public endpoints.
- A4: an evil-twin operator broadcasting a fake RESCUE_x AP.

Explicitly out of scope (state this, do not hand-wave it): nation-state
adversaries, RF jamming, and GPS spoofing. Jamming defeats any WiFi system;
the LoRa fallback partially mitigates and that is the honest answer.

## 2. Verdict on the Phase 1 controls

KEEP (these are sound, do not rip them out):
- Role separation (public / RESCUE_TEAM / HQ / SYNC_NODE). Correct shape.
- HMAC signatures on replicated records, verified at sync. This is the
  single most important control in the system: it stops A1/A4 from
  injecting forged records into the mesh. File 02 already extends it to
  all replicated tables. Keep.
- Rate limiting on public endpoints and the audit log. Keep both; add
  login attempts and MAVLink gateway events to the audit log.
- The PBKDF2 PIN + short-lived HMAC session token design from file 02.

FIX (the "nonsense" is mostly here, and the criticism is fair):
- F1. The app's certificate handling is not pinning. Accepting any
  certificate for 10.42.0.1 means TLS encrypts against passive sniffing
  but authenticates nothing: adversary A4 stands up a fake AP, presents
  any self-signed cert, and the rescue app connects. Fix: real pinning
  (section 3, plane 2).
- F2. One shared secret (NODE_SHARED_SECRET) signs everything: messages,
  sync auth, and (as planned) session tokens. A2 capturing one node owns
  the whole trust root for every purpose at once. Fix: derive per-purpose
  keys (section 3, plane 3). Physical capture remains the residual risk;
  document it with the rotation runbook as the response, and per-node
  asymmetric identities (Ed25519 + fleet trust list) as future work.
- F3. Victim flow through self-signed HTTPS. Victims hitting cert warnings
  on a captive portal is security theater with a usability cost: many
  people cannot get past mobile browser warnings, and the cert
  authenticates nothing to them anyway. Fix: victim-facing pages and
  submissions move entirely to HTTP port 80; plaintext-over-air for the
  victim plane becomes a documented accepted risk (integrity is protected
  server-side by signing at ingest; confidentiality ranked last for this
  plane in the threat model). HTTPS 8443 remains for every authenticated
  plane.
- F4. Secrets committed as files in the repo (rpi_keys.txt pattern). Never
  commit real secrets. deploy/setup_node.sh generates them into
  /etc/rescue-mesh/node.env (file 01 already does this); add .gitignore
  entries and rotate anything that was ever committed.
- F5. The new MAVLink gateway (file 08) is currently an open UDP port:
  anyone on RESCUE_S or the mesh subnet could command the drone. This is
  the largest gap in the whole system once file 08 lands. Fix: section 3,
  plane 4.
- F6. Sync/beacon replay: UDP presence beacons and pulled records need
  replay resistance. Fix: per-node monotonic counter in every signed
  beacon, receivers persist last-seen counter and reject non-increasing
  values (counter-based, not clock-based, because DRONE_S may run on
  relative time).

DROP or DEMOTE (complexity not paying rent):
- D1. mTLS between nodes: with record-level HMAC on every synced row plus
  X-Node-Auth, mutual TLS adds certificate lifecycle work for marginal
  gain in a 3-node fleet on an open IBSS link. Demote to "documented
  option, off by default". Record the reasoning (project rule 7).
- D2. E2E encryption of victim messages to a single fleet keypair whose
  private key is pasted into every rescuer phone. That is a shared secret
  wearing asymmetric clothing. Its one real benefit: message bodies on a
  captured node (A2) stay unreadable. Its real cost: one mismanaged key
  during a disaster makes pleas for help unreadable, and any rescuer
  phone leaks the "private" key. Verdict: keep the capability, OFF by
  default; discuss the tradeoff in the thesis; proper per-organization
  key management is future work, not this phase.

## 3. Target architecture, by plane

Plane 1, victim (open by necessity): open AP, HTTP port 80 portal, no
accounts. Controls: strict input validation and size caps, per-IP plus
global unauthenticated-write rate limits (per-IP alone is weak because A1
can rotate MAC/DHCP), no read-back of other victims' data, sign records at
ingest. Accepted risks, stated in writing: over-the-air plaintext, spam.

Plane 2, rescue and HQ apps: HTTPS 8443 with REAL pinning. deploy/ creates
one fleet CA at setup and issues each node its cert; the rescue app and GCC
embed the CA (SecurityContext with only that root trusted, or an explicit
SPKI/sha256 fingerprint check in badCertificateCallback). Connections to an
evil twin now fail closed. Login: personnel_id + PIN (file 02); extend
personnel.role to include HQ so GCC operators log in like everyone else,
and demote the static HQ_API_KEY to a break-glass credential stored
offline. Session tokens stay 24 h HMAC, revocation via sync.

Plane 3, inter-node: keep signed records and signed beacons, add the F6
counter, and derive purpose-separated keys with HKDF from one master
secret: K_msg (record signatures), K_sync (node auth and beacons), K_token
(session tokens). One line of cryptography library code per key; a leak of
one purpose no longer forges the others. Open IBSS stays open; the
security lives in the records, not the link.

Plane 4, drone control (highest stakes): two layers. Layer 1, network:
nftables on DRONE_S restricts UDP 14550 to the GCC's expected sources (the
10.42.0.0/24 of RESCUE_S and the volunteer-node addresses 10.99.0.1/2),
and the volunteer Pis only forward to 10.99.0.3:14550, nothing else.
Layer 2, protocol: enable MAVLink 2 packet signing between the GCC and the
flight controller with its own dedicated key (MAVLink 2 signing is
HMAC-SHA256 based and ArduPilot supports it; confidence High from official
MAVLink/ArduPilot documentation, verify exact SETUP_SIGNING steps during
file 04 Stage 1). If the chosen Dart MAVLink library turns out not to
support signing, say so in DRONE_LINK.md, compensate with layer 1 plus
control-only-from-known-paths, and record the residual risk honestly
rather than pretending.

Plane 5, physical capture (A2): accepted residual risk this phase. On
capture: rotate all secrets fleet-wide per the existing runbook, revoke
nothing else (tokens die with K_token rotation). Future work: per-node
Ed25519 identities so one captured node forges nothing fleet-wide.

## 4. Task placement (where each fix lands)

- File 01 / deploy: fleet CA + node cert issuance, .gitignore, nftables
  rules for plane 4 layer 1, HTTP-only victim portal wiring (F3, F4).
- File 02 / backend: HKDF key derivation (F2), beacon counters (F6),
  global unauthenticated-write cap (plane 1), personnel HQ role, E2E flag
  default off (D2), audit log additions.
- Files 04 and 05 / apps: real pinning against the fleet CA (F1), HQ login
  in the GCC, break-glass key path clearly labeled.
- File 08 / DRONE_S: MAVLink 2 signing setup plus the firewall (F5).

## 5. Security acceptance tests (feed into file 07 as T9)

1. Evil twin drill: clone RESCUE_A's SSID on a laptop with a different
   self-signed cert; the rescue app and GCC must refuse to connect or
   authenticate. The victim portal WILL work against the clone; state that
   as the accepted limitation of an open victim plane.
2. Token forgery: a token minted with a wrong key, an expired token, and a
   token for a REVOKED person are all rejected on every node.
3. Replay: captured sync beacon re-broadcast later is rejected (counter).
4. MAVLink: an unsigned command from a laptop on RESCUE_S is ignored by
   the FC (or blocked by nftables if signing proved unavailable); the
   signed GCC command works. Props off.
5. Rate limits: scripted flood on /message and /checkin throttles per-IP
   and globally; the node stays responsive to an already-connected rescuer.
6. Repo hygiene: git history contains no live secret after rotation;
   fresh clone plus setup script produces a working node with fresh keys.
