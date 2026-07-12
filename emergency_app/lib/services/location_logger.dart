/// LocationLogger: twice-daily background location logging (file 06).
///
/// Android background execution uses WorkManager (registerPeriodicTask).
/// Honest constraints, stated to the user in the UI and README:
///   - twice-daily needs the "Allow all the time" location permission.
///   - WorkManager's minimum period is 15 minutes and the OS may DEFER a
///     task by minutes to hours; twice-a-day is a target, not a promise.
///   - the demo verifies with a shortened interval first (file 06
///     acceptance 3), which is why logNow() exists and the period is a
///     parameter.
///
/// The background callback runs in its OWN isolate with no access to the
/// app's providers, so it talks to StorageService directly (which reads
/// and writes shared_preferences fresh each call).
library;

import 'package:geolocator/geolocator.dart';
import 'package:workmanager/workmanager.dart';

import '../constants.dart';
import '../models/stored_point.dart';
import 'storage_service.dart';

const String kLocationTaskName = 'rescue_mesh_location_log';
const String kLocationTaskUnique = 'rescue_mesh_location_log_periodic';

/// WorkManager entry point. Must be a top-level function annotated for the
/// AOT compiler so the background isolate can find it.
@pragma('vm:entry-point')
void locationCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await LocationLogger.captureOnce();
      return true;
    } catch (_) {
      // Returning true avoids WorkManager retry storms for a transient GPS
      // failure; the next scheduled run tries again.
      return true;
    }
  });
}

class LocationLogger {
  static final StorageService _storage = StorageService();

  /// Capture one point if logging is enabled and permission allows it.
  /// Used by both the background task and logNow().
  static Future<StoredPoint?> captureOnce() async {
    if (!await _storage.loggingEnabled()) return null;

    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    if (!await Geolocator.isLocationServiceEnabled()) return null;

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );
    final point = StoredPoint(
      lat: pos.latitude,
      lon: pos.longitude,
      accuracy: pos.accuracy,
      recordedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _storage.appendPoint(point);
    return point;
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(locationCallbackDispatcher);
  }

  /// Schedule the periodic background log. [period] defaults to 12 h; a
  /// shorter value (down to WorkManager's 15 min floor) is used for the
  /// demo/verification run (file 06 acceptance 3).
  static Future<void> schedule({Duration period = kLocationLogPeriod}) async {
    await Workmanager().registerPeriodicTask(
      kLocationTaskUnique,
      kLocationTaskName,
      frequency: period,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.notRequired),
    );
  }

  static Future<void> cancel() async {
    await Workmanager().cancelByUniqueName(kLocationTaskUnique);
  }

  /// Manual capture for the UI ("log a point now") and the shortened-
  /// interval verification.
  static Future<StoredPoint?> logNow() => captureOnce();
}
