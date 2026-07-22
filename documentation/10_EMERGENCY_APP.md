# 10 The Emergency (Victim) App

The emergency app is the public app for people caught in the disaster. It is
specified by `Instructions_MD_files/06_EMERGENCY_PUBLIC_APP.md` ("file 06"), was
built new in Phase 2 (Android first), and lives in `emergency_app/`. Its design
principle is privacy first: it collects the minimum, stores it locally, and only
uploads when a drone is actually in reach.

## The problem it solves

A victim may not have signal, may not know a drone is overhead, and should not
have to trust the app with their whole life. So the app:

- logs a short ring buffer of the person's own recent locations locally, so
  when a drone appears there is something useful to send;
- discovers a nearby drone over BLE (the drone's aux module advertises the
  fleet service UUID, chapter 07);
- guides the person to join that drone's Wi-Fi and then uploads their
  check-ins and, if needed, an SOS.

Unlike the rescue app, there is no login: a victim is anonymous, identified only
by a random device id generated on the phone.

## The flow

1. **Onboarding** (`screens/onboarding_screen.dart`): staged permission
   requests, explained one at a time, with the settings-intent fallback
   implemented first (so a denied permission is recoverable).
2. **Home / armed mode** (`screens/home_screen.dart`): the person "arms" the app
   when they are in a disaster area. Armed, it runs a foreground-service BLE
   watch filtered to the fleet service UUID and keeps the location ring buffer
   updated.
3. **Drone found** (`screens/drone_found_screen.dart`): when a drone is
   detected, a high-priority notification and this screen offer to join the
   drone's Wi-Fi (a settings intent, with a manual join always available).
4. **Connected** (`screens/connected_screen.dart`): once on the drone Wi-Fi,
   the app uploads its stored check-ins and offers an SOS composer. SOS check-ins
   are flagged so they stand out on the GCC map (orange).

## Privacy-first storage

`services/storage_service.dart` and `models/stored_point.dart`:

- A random `device_id` (no personal identifier).
- A location ring buffer of a small fixed number of points, captured in the
  background by `services/location_logger.dart` (WorkManager periodic task).
- A "Your data" screen (`screens/your_data_screen.dart`) that shows exactly what
  is stored and lets the person clear it.

Nothing leaves the phone until the person is connected to a drone and chooses to
upload. Uploads go to the victim plane (`POST /checkin`, chapter 06) over plain
HTTP, which is the accepted-open plane (chapter 05).

## The BLE watch, and why it finally works

`services/ble_watch_service.dart` scans for the drone's service UUID. The reason
this works in Phase 2 when Phase 1's Bluetooth never did is entirely on the
firmware side (chapter 07): the aux module puts the service UUID in the
advertising packet's complete-services *list* (AD 0x07), which is what a scan
filter matches, not only in the service *data*. The app filters on that UUID and
gets a hit. There is also a manual connect path and a live connectivity poll, so
the SOS is never trapped behind a flaky BLE detection.

## Android specifics

Because it does background location and a foreground BLE service, this app
carries the permissions the rescue app does not:
`ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE` and
`FOREGROUND_SERVICE_LOCATION`/`FOREGROUND_SERVICE_CONNECTED_DEVICE`,
`WAKE_LOCK`, and `POST_NOTIFICATIONS`, plus the same `NetworkBinder` pattern to
route uploads over the drone Wi-Fi rather than mobile data. The plugins that the
rescue app lacks (`permission_handler`, `workmanager`, `flutter_foreground_task`,
`flutter_local_notifications`, `app_settings`) live here.

A dependency note for the next team: `workmanager` was bumped from 0.5.2 to
0.9.0+3 (0.5.2 used removed Flutter embedding APIs), which renamed
`NetworkType.not_required` to `notRequired` and `ExistingWorkPolicy` to
`ExistingPeriodicWorkPolicy`; and core-library desugaring with minSdk 23 was
added for the notifications and BLE plugins.

## Building and running

- `flutter run` on Android. The privacy screens and permission flow are best
  understood by clicking through onboarding on a real device.
- `flutter analyze` clean; unit tests under `emergency_app/test/`.
- Bring-up runbook: `docs/phone_apps_bringup.html`.

## Where the code lives

```
emergency_app/lib/
  main.dart                    app entry + controller wiring
  state/app_controller.dart    the arm/found/connected state machine + connectivity poll
  services/ble_watch_service.dart    foreground BLE scan filtered on the fleet UUID
  services/location_logger.dart      WorkManager location ring buffer
  services/upload_service.dart       check-in + SOS upload (victim plane)
  services/storage_service.dart      local point storage
  services/permissions.dart          staged runtime permissions
  services/notification_service.dart drone-found notification
  services/network_binder.dart       bind uploads to the drone Wi-Fi
  screens/                     onboarding, home, drone_found, connected, your_data, settings
  models/stored_point.dart     the local point model
```
