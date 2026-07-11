# 06 EMERGENCY APP (GENERAL PUBLIC, NEW FLUTTER APP)

Goal: a lightweight app for ordinary citizens that (a) quietly keeps a small
local log of the phone's location about twice per day, (b) detects a rescue
drone's BLE advertisement and notifies the user, and (c) once the user joins
the drone WiFi, uploads the stored locations and lets them send an SOS.
New repo folder `emergency_app/`. Android is the primary target for this
phase; build iOS only if time remains (constraints below differ).

## Honest platform constraints (put these in the README and the thesis)

- No mobile OS allows an app to open itself to the foreground from a
  background BLE detection. The deliverable behavior is: detection -> high
  priority notification with sound -> user taps -> app opens on the connect
  screen. Phrase it to the panel as "automatic discovery with one-tap open".
- Background BLE scanning on Android requires either a foreground service
  (persistent "Emergency watch active" notification) or periodic short scans
  scheduled via WorkManager (roughly every 15 minutes). MVP: an explicit
  "Armed mode" toggle that starts the foreground-service scan; the periodic
  low-power scan is the stretch refinement.
- Twice-daily location needs the "Allow all the time" location permission on
  Android; schedule with WorkManager at 12 h periods (the OS may defer by
  minutes to hours; that is acceptable for this use case and should be said
  plainly rather than promising exact times).
- iOS: background scanning by service UUID works but is slow; the reliable
  wake mechanism is iBeacon region monitoring, which is why file 03 lists an
  optional iBeacon frame. Defer iOS until that exists.

## Data design (privacy is a selling point, design it deliberately)

- Local ring buffer, last 14 location points max (about 7 days), stored on
  device only (sqflite or shared prefs JSON). Nothing leaves the phone until
  the user is at a drone or presses SOS.
- device_id: random UUID generated on first run; no phone number, no name
  required. Optional display name field for rescuers.
- A visible "Your data" screen: show the stored points on a static list,
  a delete-all button, and one paragraph explaining exactly when data is
  uploaded. Examiners like this; users deserve it.

## Screens

1. Onboarding: what the app does, permission requests staged one by one with
   explanations (notifications, location while-in-use, then background
   location, then nearby-devices/BLE scan permission on Android 12+).
2. Home: status card (last logged point + time, watch armed on/off), big SOS
   button (disabled until connected to a drone, with explanation), "Your
   data" link.
3. Drone found (from notification tap): shows node name and SSID parsed from
   the BLE service data (file 03 payload `nodeId|ssid`), a JOIN WIFI button.
   Android: use the platform WiFi suggestion/specifier API via an existing
   plugin to request joining the open SSID; if the plugin path is flaky,
   fall back to a one-tap "Open WiFi settings" intent with the SSID shown
   large. Implement the fallback FIRST; it always works.
4. Connected flow: on gaining connectivity to 10.42.0.1, POST /checkin with
   the stored points (mark uploaded_at locally), then show the SOS composer
   (short text, optional current GPS attach) which posts a checkin with
   sos=true so it enters the rescue message queue (file 02 behavior).
5. Settings: language (Sinhala/Tamil/English at least as a stub structure),
   logging on/off, data deletion.

## Deferred by decision (record in README)

- The national "emergency state" trigger server (a normal-times cloud service
  that flips clients into emergency mode and could raise the logging rate)
  is OUT OF SCOPE this phase. Leave a config flag `emergencyMode` that the
  UI toggle controls manually for the demo, with a comment pointing at the
  future server integration.

## Acceptance

1. With the app in Armed mode and the phone locked, powering an aux module
   30 m away produces a notification within 60 s; tapping it lands on the
   Drone found screen with the right SSID.
2. After joining RESCUE_A, stored points appear in the GCC map (checkins
   layer) within one poll cycle; SOS appears in the rescue app's requests.
3. Two forced location logs 12 h apart appear in "Your data" without the app
   being opened in between (verify with a shortened test interval first,
   then one real 12 h run).
4. Uninstall/reinstall produces a new device_id and an empty log (privacy
   check).
