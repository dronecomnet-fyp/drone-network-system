# 05 RESCUE APP UPDATE: PIN LOGIN AND ALIGNMENT WITH BACKEND V2

Applies to the existing Flutter app (rescue_person_app_ files). Keep the
current architecture (Provider, APIService, secure storage, cert pinning to
10.42.0.1). This package depends on file 02's /auth endpoints.

## Task 5.1 Login flow

- New LoginScreen shown when no valid session token exists: fields
  personnel_id + PIN, connect hint text ("join any RESCUE_x WiFi first").
- POST /auth/login -> store {token, expires_at, personnel_id} in
  flutter_secure_storage.
- APIService: send X-Session-Token on privileged calls when a token exists;
  fall back to X-API-Key if an admin key is configured in Settings (keep the
  existing manual-key path as the break-glass/admin mode, clearly labeled).
- 401/403 handling: clear token, route to LoginScreen with a message that
  distinguishes expired vs revoked when the backend provides it.
- Logout button in Settings.

## Task 5.2 Use the identity

- claim calls send claimed_by = personnel_id (backend stores it, v3 schema);
  requests list shows "claimed by R-014" instead of an anonymous green badge.
- HQ uplink sender field auto-fills from personnel_id (editable).
- Attach GPS to uplink using the geolocator dependency that is already in
  pubspec but appears unused for this purpose; respect the existing optional
  location fields on /gs-uplink.

## Task 5.3 Contract alignment

- Update Message model to schema v3 fields (user_lat/user_lon/node_lat/
  node_lon/time_source/node_id/claimed_by). Show time_source subtly (e.g. a
  small "~" prefix when relative) so rescuers know an early timestamp is
  approximate; this is a nice examiner detail from design v3 3.3.
- Announcements screen: point it at the real /announcements endpoints from
  file 02 and verify end to end (the screen predates the backend support).
- Health strip (optional, small): current node battery and GPS from /health
  in the Settings screen, useful during field tests.

## Task 5.4 Keep and verify

- Cert-pinning behavior (_buildClient host allowlist) unchanged.
- E2E decryption service unchanged; verify against v3 message payloads.
- Polling stays 5 s; do not add websockets in this phase.

## Acceptance

1. Fresh install -> join RESCUE_B -> login with a PIN issued on drone A via
   the GCC -> requests load using the token, no API key ever typed.
2. Claim shows claimed_by on another device connected to a different drone
   after sync.
3. Revoked personnel: next API call after token expiry or next login attempt
   fails with a clear message.
4. Announcements published from the GCC appear in the app.
