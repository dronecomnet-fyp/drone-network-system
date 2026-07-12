# rescue_app: rescue personnel mobile app (file 05, Phase 2)

Flutter app for rescue teams: PIN login, victim requests with claim
identity, HQ field reports, real HQ announcements. Phase 1 architecture
kept (Provider, static APIService facade, flutter_secure_storage);
transport and the wire contract now come from the shared
rescue_mesh_shared package, the same one the GCC uses.

## What changed vs Phase 1 (files 05 + 09)

- LOGIN: personnel_id + PIN issued by HQ in the GCC. The signed session
  token verifies OFFLINE on any node, so one login works across the whole
  fleet. 401 (expired) and 403 (revoked) are told apart, the session is
  cleared, and the login screen explains which one happened.
- CLAIMS carry identity: the backend stamps claimed_by from the token;
  the list shows "CLAIMED by R-014" instead of an anonymous green badge.
- REAL pinning (file 09 F1): Phase 1 accepted ANY certificate for
  10.42.0.1, which authenticated nothing. Now the app trusts only the
  fleet CA pasted in Settings and fails closed otherwise: an evil twin
  broadcasting a fake RESCUE_x cannot authenticate to this app. A labeled
  dev-only insecure toggle exists for the bench.
- Schema v3: user vs node coordinates, time_source with a "~" prefix on
  approximate (pre-GPS-fix) timestamps, node_id + synced_from provenance.
  Free-text landmarks now live inside the message content (the portal
  folds them in before optional encryption).
- Announcements screen shows REAL /announcements (the Phase 1 screen
  displayed gs_messages as a stand-in; field reports still show on the
  HQ Uplink screen's log).
- HQ uplink sender autofills from the logged-in identity (editable; the
  backend prefers token identity anyway) and can attach GPS via
  geolocator.
- Settings: fleet CA paste, node health strip (battery/GPS/clock of the
  connected node), logout, and the API key relabeled as the break-glass
  admin path (optional; PIN login is the normal path). The E2E private
  key is now optional because E2E is off by default (file 09 D2).

## Build and test

```
cd rescue_app
flutter pub get
flutter analyze        # zero errors/warnings (info-level style lints
                       # match the Phase 1 baseline)
flutter test           # 11 tests: v3 model mapping, ~ time hint,
                       # login gate, session expiry, break-glass mode
flutter build apk --debug
```

Local end-to-end: start a backend node from backend/ (see
tools/local_two_node_test.sh for the env recipe), issue a PIN with curl
or the GCC, point the app's Settings at http://<mac-ip>:18543 from a
phone on the same network, and log in.

## Acceptance mapping (file 05)

1. Fresh install -> join RESCUE_B -> login with PIN issued on drone A:
   implemented; field check needs the rebuilt fleet (backend side proven
   by tools/local_two_node_test.sh).
2. claimed_by visible on another device after sync: implemented (UI +
   backend conflict rules tested).
3. Revoked personnel: clear expired-vs-revoked messages implemented.
4. Announcements published from the GCC appear here: implemented against
   the real endpoints.
