/// Staged permission requests (file 06 onboarding): asked ONE AT A TIME
/// with explanations, in the order the platform prefers:
///   1. notifications (so the drone-found alert can appear)
///   2. location while-in-use
///   3. background location ("Allow all the time", needed for twice-daily
///      logging)
///   4. nearby-devices / BLE scan (Android 12+)
library;

import 'package:permission_handler/permission_handler.dart';

class Permissions {
  static Future<bool> requestNotifications() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<bool> requestLocationWhenInUse() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  /// Background location must be requested AFTER while-in-use is granted
  /// (Android requirement). The user is sent to the "Allow all the time"
  /// choice.
  static Future<bool> requestLocationAlways() async {
    final status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  /// Android 12+ nearby-devices scan permission. On older Android this is
  /// covered by location and returns granted.
  static Future<bool> requestBleScan() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted || s.isLimited) ||
        // Older Android: BLE scanning rides on location permission.
        (await Permission.locationWhenInUse.isGranted);
  }

  static Future<Map<String, bool>> currentStatus() async => {
        'notifications': await Permission.notification.isGranted,
        'locationWhenInUse': await Permission.locationWhenInUse.isGranted,
        'locationAlways': await Permission.locationAlways.isGranted,
        'bluetoothScan': await Permission.bluetoothScan.isGranted ||
            await Permission.locationWhenInUse.isGranted,
      };
}
