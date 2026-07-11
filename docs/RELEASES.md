# GCC releases (file 04 screen 8)

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

| Version | Date | Built by | Notes |
|---------|------|----------|-------|
| (none yet) | | | first release follows the fleet rebuild + field VERIFY |
