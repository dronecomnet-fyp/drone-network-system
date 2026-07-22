# 09 The Rescue Personnel App

The rescue app is the phone app a rescue team member uses in the field. It is
specified by `Instructions_MD_files/05_RESCUE_APP_UPDATE.md` ("file 05"), was
carried forward from the Phase 1 rescue app and rebuilt, and lives in
`rescue_app/`. It shares its models and API client with the other apps through
`shared_dart`.

## What a rescuer does with it

1. Joins a `RESCUE_x` Wi-Fi (the drone's access point).
2. Logs in with the personnel id and PIN that HQ issued them.
3. Sees victim requests, claims the ones they will respond to (recording their
   own identity), and files field reports back to HQ.
4. Reads announcements.
5. While logged in and using the app, quietly shares their location so the GCC
   can see where teams are.

## Structure

Four tabs behind a login gate. `rescue_app/lib/main.dart` shows a `LoginScreen`
until a valid session exists (`RootGate`), then the four-tab `MainApp`:

- `screens/victim_requests_screen.dart`: the victim message feed with claim.
- `screens/hq_uplink_screen.dart`: file a field report (with an optional
  one-shot GPS location) to HQ.
- `screens/announcements_screen.dart`: operational notices.
- `screens/settings_screen.dart`: connection, the fleet CA, the break-glass
  key, the node health strip, and the "Share my location" toggle.

State is `provider`-based:

- `providers/auth_provider.dart`: the login session lifecycle. The session
  token is stored in `flutter_secure_storage` and reloaded on startup. The app
  distinguishes 401 (credential dead, re-login) from 403 (wrong role, stay
  logged in), which is a real correctness requirement (chapter 05).
- `providers/message_provider.dart`: polls messages/announcements on a
  self-rescheduling timer with adaptive backoff (5 s normally, doubling up to
  2 minutes on failure), pausing on credential failure.
- `providers/heartbeat_provider.dart`: the location heartbeat (below).

## The networking layer

The app never talks HTTP directly. `services/api_service.dart` is a static
facade that builds a `RescueMeshClient` (from `shared_dart`) per call, injecting
the session token, and maps transport errors to typed app errors
(`networkError` "Cannot reach the drone", `timeout`, `pinningFailed`, and the
HTTP status codes). The base URL defaults to `https://10.42.0.1:8443`.

Two Android-specific pieces make it work on a no-internet Wi-Fi:

- **The INTERNET permission is declared in the release manifest.** Flutter only
  adds it to the debug manifest automatically, so a release build without it
  cannot make any network call. This was a real shipped bug.
- **A network binder** (`services/network_binder.dart`, a MethodChannel to
  Kotlin) binds the app's traffic to the Wi-Fi transport with a
  `NetworkRequest` that drops the INTERNET capability requirement. Without this,
  Android routes traffic to mobile data, where `10.42.0.1` has no route, and
  everything fails. The binding is applied at startup and takes effect even if
  the user joins the Wi-Fi later.

## The location heartbeat (M7d)

Added in the mission layer. `providers/heartbeat_provider.dart` sends the
rescuer's location to the node about every 90 seconds, but **only while logged
in and with the app in the foreground**. Nothing runs in the background or when
logged out. That is the deliberate battery tradeoff: the operator sees each
rescuer's last-known position with its age, not a continuous live stream.

- It uses the existing `geolocator` dependency at medium accuracy with a
  10 second timeout, falling back to the last known position, and skips a beat
  on failure with the same adaptive backoff as the message poller.
- It is wired to the login state (a proxy provider) and the app lifecycle (a
  `WidgetsBindingObserver` in `main.dart`), and it has a "Share my location"
  toggle in Settings, on by default, showing when it last sent.
- The backend stores the position under the rescuer's token identity (never the
  request body) in the signed, replicated `personnel_locations` table, so it
  syncs fleet-wide and the GCC shows it (chapter 12). Rolling this out to the
  nodes needed only a code update and an automatic table creation; the runbook
  is `deploy/node_update_locations.html`.

Continuous background tracking (a foreground service with WorkManager) is
documented future work, not built. The emergency app already has that pattern
(`emergency_app/lib/services/location_logger.dart`) if the next team wants it.

## Building and running

- `flutter run` on an Android device or emulator.
- Release APK steps are in the app's README; the phone bring-up runbook is
  `docs/phone_apps_bringup.html`.
- `flutter analyze` reports zero errors and zero warnings (the project enables a
  large set of style lints that surface as info only).

## Where the code lives

```
rescue_app/lib/
  main.dart                     login gate + four-tab shell + lifecycle observer
  providers/                    auth, message poller, location heartbeat
  services/api_service.dart     static facade over RescueMeshClient
  services/network_binder.dart  bind traffic to the drone Wi-Fi (Kotlin channel)
  services/message_crypto_service.dart  optional E2E (off by default)
  screens/                      requests, HQ uplink, announcements, login, settings
  config/api_config.dart        base URL, secure-storage session store
```
