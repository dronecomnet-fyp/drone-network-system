# Field Share: handing out the app and offline maps with no internet

At a disaster site there is no internet and no app store, yet rescue
personnel arriving on scene still need the rescue app installed and the
right offline region maps on their phones. Field Share turns the ground
laptop (the Ground Control Center) into a small local download point so
they can self-serve over local Wi-Fi.

This is the GCC "Field Share" tab. It runs a plain HTTP server on the
laptop and shows a link plus a QR code; phones on the same Wi-Fi open that
link in a browser and download the files.

## Before you go (prepare the bundle)

While you still have internet, copy the field bundle onto the laptop (or
onto a USB stick you carry):

- `rescue_app.apk` (the rescue personnel app; build it with
  `flutter build apk --release` in `rescue_app/`, output under
  `rescue_app/build/app/outputs/flutter-apk/`)
- one or more `.mbtiles` region map files for the operation area
  (preparation is described in docs/OFFLINE_MAPS.md)
- optionally the emergency app APK and any printed-to-PDF instructions

Put them all in ONE folder. Field Share shares the top-level files of that
folder.

## On site (start sharing)

1. Give everyone one local network with no internet required:
   - a small travel/battery router that the laptop and phones all join, OR
   - the laptop's own Wi-Fi hotspot.
   Field Share does not create the network; it serves over whatever local
   Wi-Fi the laptop is on.
2. Open the GCC, go to the "Field Share" tab.
3. "Choose folder" and pick the bundle folder. The file list appears.
4. Tap "Start sharing". The tab now shows a QR code and a link such as
   `http://10.42.0.1:8080/`.

The server keeps running while you use other GCC tabs. Tap "Stop sharing"
to shut it down; "Rescan folder" if you copy more files across.

## For personnel (download)

1. Join the same Wi-Fi as the laptop (no internet needed).
2. Scan the QR code shown on the laptop, or type the link into a phone
   browser.
3. A plain page lists the files. Tap one to download it.
4. To install the APK, Android asks once to allow "install from unknown
   sources" for the browser. Allow it, then open the downloaded APK.
5. Open the app, then load any downloaded `.mbtiles` map file from the
   app's map settings.

## Scope and safety (stated honestly for the thesis)

- Field Share serves ONLY the top-level files of the folder you choose,
  over plain HTTP, on the LOCAL network. This is a deliberate hand-out of
  public installers and map files, not sensitive data.
- There is no upload path (download only), and requested filenames are
  validated so a request cannot escape the chosen folder.
- Plain HTTP (not HTTPS) is acceptable here because the data is public and
  the network is a closed local one you control. Do not put anything
  private in the shared folder.
- Platform: the demo runs under `flutter run` on macOS (the dev build
  already carries the macOS network-server entitlement) and on the Windows
  delivery build (no entitlement needed). Confidence: High for Windows and
  macOS debug; the macOS release target is not maintained for networking
  (see CHANGES.md item 29).
