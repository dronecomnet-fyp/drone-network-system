# Releases: the GCC desktop app and the phone APKs

Two delivery channels, documented together because the phone one drifted
once already: the APKs on the GitHub release sat four commits behind the
code while the runbooks told people to install them, so a documented
verification step referred to a Settings toggle that was not in the
published build. Anything that changes `rescue_app/`, `emergency_app/`, or
`shared_dart/` needs a new APK release, not just a commit.

## Phone apps: Android APK release

Built on any machine with the Flutter Android toolchain (macOS is fine,
unlike the Windows-only GCC build below).

1. Bump the version in the app's `pubspec.yaml` (`version: X.Y.Z+build`).
   The build number must increase or Android refuses the upgrade.
2. Build both apps:

   ```text
   cd rescue_app    && flutter test && flutter build apk --release
   cd ../emergency_app && flutter test && flutter build apk --release
   ```

   Output: `<app>/build/app/outputs/flutter-apk/app-release.apk`.
3. Rename by app and version (`rescue-app-v2.1.apk`), then publish:

   ```text
   gh release create phone-apps-vN --title "..." --notes "..." \
       rescue-app-vX.Y.apk emergency-app-vX.Y.Z.apk
   ```

   Cut a NEW tag rather than replacing assets on an old one, so "which
   build was on that phone" stays answerable after the fact.
4. Update the release log at the bottom of this file.

### Signing, and why upgrades can fail

`android/app/build.gradle.kts` still carries Flutter's default TODO: the
release build is signed with the **debug keystore**
(`~/.android/debug.keystore`), which is per-machine, not per-project.

Consequence: APKs built on a DIFFERENT machine than the previous release
have a different signature, and Android refuses to install them over the
existing app ("App not installed"). The user has to uninstall first, which
loses local app data.

So either keep building releases on the same machine, or add a real
keystore (gitignored `key.properties` + a `signingConfig`; the keystore
itself must NEVER be committed). Check before publishing:

```text
apksigner verify --print-certs <new>.apk    # compare the SHA-256 digest
```

Confidence: High, this is standard Android signing behaviour.

### Distributing to phones in the field

There is no app store at a disaster site. Put the APKs (and the region
`.mbtiles`) in one folder and serve them from the GCC "Field Share" tab
over a local router or hotspot; personnel scan the QR and download. See
docs/FIELD_SHARE.md.

## GCC releases (file 04 screen 8)

The GCC is delivered to the ground laptop as an INSTALLED Windows app,
not a dev build. Development happens on macOS/Linux; the release build
MUST run on a Windows machine (Flutter cannot cross-compile Windows
desktop builds).

## Build a release (on Windows)

1. Install Flutter (stable channel; the repo was developed on 3.41.x)
   and Visual Studio with the "Desktop development with C++" workload
   (Flutter Windows desktop requirement).
2. `git clone <repo>` and:
   ```
   cd gcc_app
   flutter pub get
   flutter test
   flutter build windows --release
   ```
3. The app is produced in `gcc_app/build/windows/x64/runner/Release/`.
   That folder is self-contained (exe + DLLs + data/).

## Package

Portable zip (chosen for simplicity; an MSIX installer is the upgrade
path if the supervisor wants Start-menu integration):

1. Zip the whole Release folder as `gcc_app_vX.Y.Z_windows_x64.zip`
   (version from gcc_app/pubspec.yaml).
2. Include in the zip root: a copy of this file's "Install on the ground
   laptop" section as INSTALL.txt, and the fleet CA public cert
   (fleet_ca.crt) so the operator can load it in Settings on first run.
   NEVER include fleet_ca.key or fleet_secrets.env.

## Install on the ground laptop

1. Unzip anywhere (e.g. C:\\rescue-gcc\\). Run gcc_app.exe.
2. First-run setup in the Settings tab:
   - load fleet_ca.crt (HTTPS fails closed until this is done, by design)
   - load the mission region .mbtiles (docs/OFFLINE_MAPS.md)
   - log in with an HQ personnel PIN (or the break-glass key for a fresh
     fleet whose personnel table is empty)
3. Join a RESCUE_x WiFi and confirm the Nodes tab shows the node.

## Release log

### Phone APKs (GitHub releases)

| Tag            | Date       | Apps                             | Notes |
|----------------|------------|----------------------------------|-------|
| phone-apps-v1  | 2026-07-15 | rescue 2.0.0, emergency 0.1.0    | first sideload test builds against DRONE_A |
| phone-apps-v2  | 2026-07-28 | rescue 2.1.0, emergency 0.1.1    | rescue: location heartbeat + Share my location toggle, LoRa-fallback alert banner, ops map tab, field bug fixes. emergency: field bug fixes. Same debug signing key as v1, so both install over the top. |
| phone-apps-v3  | 2026-08-03 | rescue 2.2.0, emergency 0.2.0    | emergency: conversation screen with three delivery states, area map, opens itself on a drone sighting, notification spam fix. rescue: reply to a victim with quick replies. Same signing key again. |
| phone-apps-v4  | 2026-08-05 | rescue 2.3.0, emergency 0.3.0    | rescue: sign in by scanning one QR, works on a drone that has never met the rescuer (carries the signed record plus the PIN; see CHANGES 41 for the posture trade). emergency: tappable SOS options fetched from the node so the app and the captive portal always agree, and location became opt out rather than a silent attachment. Same signing key again. Nodes must be updated first (`docs/node_update_lora_log.html`) or the app falls back to its built-in option list. |

### GCC desktop

| Version | Date | Built by | Notes |
|---------|------|----------|-------|
| (none yet) | | | first release follows the fleet rebuild + field VERIFY |
