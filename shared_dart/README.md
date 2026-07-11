# rescue_mesh_shared

Shared models and API client for the three rescue mesh apps: the GCC
desktop app (file 04), the rescue personnel app (file 05), and the
emergency app (file 06). One package keeps the backend contract in one
place; pure Dart so `dart test` runs against a live backend node.

- `Message`, `GsMessage`, `Announcement`, `Personnel`, `Checkin`,
  `NodeHealth`, `AuthSession`: mirror backend schema v3 field names.
- `RescueMeshClient`: token-first auth (X-Session-Token from PIN login,
  X-API-Key break-glass fallback) and REAL fleet-CA pinning (file 09 F1):
  https connections trust ONLY the supplied fleet CA and fail closed
  otherwise. `allowInsecure` exists for dev and must be labeled in UIs.

Certificate note (verified empirically): Dart's BoringSSL requires
keyUsage on the CA and keyUsage + extendedKeyUsage=serverAuth on the node
cert; deploy/make_fleet_ca.sh and deploy/setup_node.sh already issue
exactly that. Do not hand-roll certs without those extensions.

Tests: `dart test` starts real backend instances from ../backend (venv
required) and covers the full contract plus the T9.1 pinning drill
(fleet CA connects, wrong CA fails closed, no CA fails closed).
