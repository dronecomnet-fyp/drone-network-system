# emergency_app: public emergency app (file 06)

A lightweight app for ordinary citizens. It (a) keeps a small local
location log about twice a day, (b) detects a rescue drone's BLE
advertisement and notifies the user, and (c) once the user joins the
drone WiFi, uploads the stored locations and lets them send an SOS.
Android is the primary target this phase.

## Honest platform constraints (also in the thesis)

These are real OS limits, stated plainly rather than hidden:

- No mobile OS lets an app bring itself to the foreground from a
  background BLE detection. The deliverable behavior is: detection ->
  high-priority notification with sound -> user taps -> app opens on the
  Drone found screen. Phrased for the panel as "automatic discovery with
  one-tap open" (master plan R4).
- Background BLE scanning on Android needs a foreground service (a
  persistent "Emergency watch active" notification). The MVP is an
  explicit Armed-mode toggle that starts that service and scans; the
  periodic low-power WorkManager scan is the stretch refinement and is
  NOT built this phase.
- Twice-daily location needs the "Allow all the time" location
  permission. It is scheduled with WorkManager at a 12 h period; the OS
  may defer a task by minutes to hours, and WorkManager's minimum period
  is 15 minutes. Twice a day is a target, not a promise.
- iOS: background scanning by service UUID works but is slow; the
  reliable wake mechanism is iBeacon region monitoring (file 03 lists an
  optional iBeacon frame). iOS is deferred until that exists.

## Privacy (a design goal, file 06 data design)

- Location ring buffer: last 14 points (about 7 days at 2/day), stored on
  device only. Nothing leaves the phone until the user is at a drone or
  presses SOS.
- device_id: a random UUID generated on first run. No phone number, no
  name required; an optional display name for rescuers.
- A visible "Your data" screen: the stored points as a list (with which
  ones have been sent), a delete-all button, and one paragraph on exactly
  when data is uploaded.
- Uninstall/reinstall produces a new device_id and an empty log
  (file 06 acceptance 4).

## Screens

| Screen | What |
|--------|------|
| Onboarding | Staged permission requests, one at a time with reasons: notifications, while-in-use location, background location, BLE scan |
| Home | Watch armed on/off, last logged point, big SOS button (disabled until on a drone, with the reason), link to Your data |
| Drone found | From the notification tap: node name + SSID from the BLE service data, JOIN WIFI (open Wi-Fi settings with the SSID shown large and copied; the always-works fallback is implemented FIRST per file 06) |
| Connected | On drone connectivity: uploads stored points via POST /checkin (marking them locally), then an SOS composer that posts a checkin with sos=true so it enters the rescue message queue |
| Your data | Privacy screen: stored points, sent/on-phone status, delete-all |
| Settings | Logging on/off, log-a-point-now (also the shortened-interval test), emergency-mode demo flag, language stub (Sinhala/Tamil/English), data deletion |

## BLE contract

The armed scan filters on the project-fixed service UUID
`2b57461c-1c04-49c4-944a-13643c1618da` (firmware file 03), so only rescue
drones trigger anything. Service data carries `nodeId|ssid`; both are
parsed for the notification and the Drone found screen.

## Deferred by decision (file 06)

The national "emergency state" trigger server (a normal-times cloud
service that flips clients into emergency mode and could raise the
logging rate) is OUT OF SCOPE this phase. A manual `emergencyMode` flag
in Settings stands in for the demo; the code comments point at the future
server integration.

## Build and test

```
cd emergency_app
flutter pub get
flutter analyze        # clean
flutter test           # 9 unit tests (BLE parse, ring buffer, upload shape)
flutter build apk --debug
```

Local end-to-end: run a backend node from backend/ (victim plane on
HTTP), set kDroneBaseUrl if testing off-device, and POST a checkin; the
SOS path is covered by the shared package's live test
(shared_dart: "emergency-app checkin upload with SOS").

## Acceptance mapping (file 06)

1. Armed + locked phone -> aux module powered 30 m away -> notification
   within 60 s -> Drone found screen with the right SSID: needs a flashed
   aux module (hardware); the notification + parse path is implemented and
   unit tested.
2. After joining RESCUE_A, stored points on the GCC map + SOS in the
   rescue app: the upload contract is proven by the shared live test; the
   full pipeline is a file 07 T6 hardware run.
3. Two forced logs 12 h apart appear in Your data without opening the
   app: implemented via WorkManager; verify with a shortened interval
   first (Settings > log a point now, and a 15 min period) then one real
   12 h run.
4. Uninstall/reinstall -> new device_id, empty log: by construction
   (state lives only in app storage).
