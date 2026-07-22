# 05 Security Architecture

The security design is the cross-cutting spine of Phase 2. It is specified in
`Instructions_MD_files/09_SECURITY_ARCHITECTURE.md` (referred to as "file 09")
and applied inside the backend, deploy, and app packages. This chapter explains
the threat model, the mechanisms, and where they live. The ground rule for the
whole project: the security posture changes only as file 09 specifies; anything
not listed there stays as Phase 1 built it.

## The threat model: five planes

The system is reasoned about as five planes, each with different trust
assumptions. Designing per plane keeps each control proportionate.

1. **Victim plane** (open by necessity). A victim cannot be asked to install an
   app or trust a certificate. So this plane is plain HTTP. Confidentiality is
   sacrificed; integrity and availability are protected instead (messages are
   signed at ingest and rate-limited).
2. **Rescue and HQ plane**. Authenticated users on managed devices. HTTPS with
   real certificate pinning; PIN login and session tokens.
3. **Inter-node plane**. Nodes trust each other only as far as a shared secret
   proves. Every synced record is signed and verified; beacons are signed and
   replay-protected.
4. **Drone control plane** (highest stakes). A bad actor here could move a
   drone. Protected by network isolation (firewall) and a liveness gate;
   MAVLink signing is recorded as residual risk.
5. **Physical capture plane**. If a drone is physically captured, its secrets
   are exposed. This is an accepted residual risk; the response is key rotation.

## Keep, fix, demote

File 09 sorted every Phase 1 control into keep, fix, or demote. The result:

**Kept** (Phase 1 got these right): role separation, per-record HMAC signatures
verified at sync, per-IP rate limits, the audit log, and PBKDF2 for PINs.

**Fixed** in Phase 2:

- **One shared secret became three purpose-separated keys (F2).** See below.
- **The victim flow moved to plain HTTP port 80 (F3).** See below.
- **No secrets in git, ever (F4).** Secrets are generated at deploy time;
  anything that ever touched the old repos is treated as burned and rotated.
- **Beacon replay defence (F6):** the per-node monotonic counter (chapter 04).
- **A global unauthenticated-write cap** on top of per-IP limits (plane 1).
- **A fleet certificate authority** issuing per-node certificates (plane 2),
  replacing self-signed-accept-anything.

**Demoted** (kept as capabilities but off by default, with recorded reasons):
inter-node mutual TLS (per-record HMAC already covers the need in a three-node
fleet) and fleet-keypair end-to-end victim encryption (a private key pasted
into every rescuer phone is a shared secret in asymmetric clothing, and a
mismanaged key mid-disaster makes pleas for help unreadable).

## Mechanism 1: purpose-separated keys (HKDF)

The single most important security change. In Phase 1 one secret signed
everything, so capturing it compromised every trust purpose at once.

Phase 2 derives three keys from one `NODE_MASTER_SECRET` using HKDF-SHA256
(`backend/crypto_keys.py`):

- **K_MSG** signs replicated records (messages, personnel, announcements,
  gs_messages, checkins, personnel_locations). Verified at every sync.
- **K_SYNC** authenticates inter-node traffic: the `X-Node-Auth` header on sync
  pulls, and the signature on presence beacons.
- **K_TOKEN** signs personnel session tokens.

A leak of one purpose forges nothing else. The master secret is the same across
the fleet (all nodes must verify each other), so physical capture of any node
still exposes it; that is the accepted residual risk, and the response is key
rotation (regenerate the fleet secrets and re-issue node certificates, then
redeploy). Per-node Ed25519 identities, which would remove the shared-secret
exposure entirely, are recorded as future work, not this phase.

Every table has a canonical payload function and `sign_record` / `verify_record`
helpers in `backend/models.py`. The signature covers the identity fields, not
the mutable workflow state: changing a message's claim status requires K_SYNC
possession (sync-plane authority), while forging a record requires K_MSG. This
mirrors Phase 1's choice to sign only identity fields.

## Mechanism 2: the two planes (HTTP 80 and HTTPS 8443)

The node runs two separate web services (chapter 06):

- **Victim plane**, `backend/http_app.py`, plain HTTP on port 80. The captive
  portal and the victim message form only. Plaintext-over-air here is a written
  accepted risk (F3): a victim hitting a certificate warning is a usability cost
  with no authentication value to them, and victim-message *integrity* (signed
  at ingest) and *availability* outrank confidentiality in this threat model.
- **Authenticated plane**, `backend/api.py`, HTTPS on port 8443, for every
  rescuer/HQ/sync operation.

Splitting them means the open plane can never accidentally expose an
authenticated endpoint.

## Mechanism 3: the fleet CA and real pinning

Phase 1 apps "pinned" by accepting any certificate for `10.42.0.1`, which is
not pinning; an evil-twin access point with its own certificate would be
trusted.

Phase 2:

- `deploy/make_fleet_ca.sh` generates one fleet certificate authority into
  `deploy/secrets/` (git-ignored, carried by the operator). This is run once.
- `deploy/setup_node.sh` issues each node a certificate signed by that CA, for
  the 8443 API.
- The apps embed the CA's public certificate and trust **only** that root
  (`shared_dart/lib/src/client.dart` builds a `SecurityContext` with
  `withTrustedRoots: false` and the pasted fleet CA). A connection whose
  certificate does not chain to the fleet CA fails closed. An evil twin is
  rejected.

A real bench finding is captured here: Dart's BoringSSL requires the CA to
carry `keyUsage` and the leaf to carry `keyUsage` plus extended-key-usage
`serverAuth`, or pinning silently fails. The deploy scripts issue certificates
with those extensions.

**Never run `make_fleet_ca.sh` on DRONE_B or DRONE_S.** They must copy
DRONE_A's `deploy/secrets/`. A different key set means the nodes silently reject
each other and never sync. This is the single most common setup mistake.

## Mechanism 4: PIN login and session tokens

Personnel authentication (chapter 03 gap 4):

- HQ issues a rescuer a one-time PIN (`POST /personnel` returns the plaintext
  PIN exactly once). The PIN is stored only as a PBKDF2-SHA256 hash (>= 200,000
  iterations) with a per-record salt.
- The rescuer logs in (`POST /auth/login`, rate-limited per IP and per
  personnel id because PINs are low entropy). On success they receive a
  **stateless session token**: `base64url(payload).HMAC_K_TOKEN(payload)`, where
  the payload is `{personnel_id, role, exp}`.
- Because it is an HMAC over K_TOKEN and every node has K_TOKEN, **any node can
  verify the token offline**, without contacting the issuer. This matters in a
  DTN where the issuing node may be out of range.
- On every authenticated request, `get_auth` verifies the token signature and
  expiry, then re-checks the personnel record is still ACTIVE in the local
  (synced) table. A revoked rescuer's token dies at its next use fleet-wide,
  because revocation propagates as a personnel row (REVOKED beats ACTIVE).

An important distinction the apps rely on: **401 means the credential is dead**
(expired token, revoked personnel) and the app must re-authenticate; **403
means wrong role** (logged in fine, not allowed here) and must never log the
user out. Getting this wrong caused a real Phase 2 bug where rescuers were
logged out whenever they touched an HQ-only endpoint.

The static HQ API key still exists but is demoted to a clearly-labelled
break-glass credential for when the personnel table is empty (a fresh fleet).

## Mechanism 5: rate limits and audit

- Per-IP sliding-window rate limits plus a global unauthenticated-write cap on
  the victim plane (`backend/ratelimit.py`), so one device cannot flood the
  fleet and the fleet as a whole has a ceiling.
- An audit log (`backend/audit.py`) records logins, claims, syncs, beacon
  rejects, and clock changes.

## The drone control plane

The highest-stakes plane gets its own treatment in chapter 11. In short: the
MAVLink UDP port is firewalled (`deploy/files/nftables-drone-s.nft`) to accept
only the local user subnet and the volunteer mesh addresses (file 09 plane 4
layer 1); every command in the GCC is gated on a MAVLink heartbeat fresher than
two seconds; and MAVLink 2 packet signing (layer 2) is recorded as honest
residual risk and future work.

## Where the code lives

- Key derivation and tokens: `backend/crypto_keys.py`
- Record signing and verification: `backend/models.py`
- Auth resolution and login: `backend/api.py` (`get_auth`, `require_roles`,
  `/auth/login`)
- Rate limits: `backend/ratelimit.py`; audit: `backend/audit.py`
- Fleet CA and node certs: `deploy/make_fleet_ca.sh`, `deploy/setup_node.sh`
- App-side pinning: `shared_dart/lib/src/client.dart`
- Firewall: `deploy/files/nftables-drone-s.nft`, `nftables-volunteer.nft`
- The security drills: chapter 15 (T9), `docs/test_log.md`
