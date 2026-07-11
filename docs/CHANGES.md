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
