/// BleWatchService: armed-mode Bluetooth watch for a rescue drone
/// (file 06 MVP).
///
/// Design honesty (put in the README and thesis, master plan R4):
///   - No mobile OS lets an app foreground itself from a background scan.
///     Achievable behavior: detect -> high-priority notification -> user
///     taps -> app opens on the Drone found screen.
///   - Continuous background BLE scanning on Android needs a foreground
///     service with a persistent notification. MVP is an explicit "Armed
///     mode" toggle that starts that service and scans; the periodic
///     low-power WorkManager scan is the stretch refinement, not built.
///
/// The scan filters on the project-fixed service UUID (constants.dart /
/// firmware file 03), so only rescue drones trigger anything. Service data
/// carries `nodeId|ssid`; both are parsed for the notification and the
/// Drone found screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../constants.dart';
import 'notification_service.dart';

/// Foreground-service entry point. It exists only to keep the app process
/// alive so the main-isolate scan keeps running while the screen is off;
/// the scanning itself lives in BleWatchService (main isolate) where the
/// flutter_blue_plus plugin and app state are available.
@pragma('vm:entry-point')
void bleForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveTaskHandler());
}

class _KeepAliveTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}

class DroneSighting {
  final String nodeLabel;
  final String ssid;
  final int rssi;
  final DateTime seenAt;

  const DroneSighting({
    required this.nodeLabel,
    required this.ssid,
    required this.rssi,
    required this.seenAt,
  });
}

class BleWatchService {
  final _guid = Guid(kRescueServiceUuid);
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _armed = false;

  /// Called on every fresh sighting (UI updates its status card).
  void Function(DroneSighting sighting)? onSighting;

  bool get isArmed => _armed;

  static Future<void> initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'rescue_watch',
        channelName: 'Emergency watch',
        channelDescription:
            'Shown while the app is watching for a nearby rescue drone.',
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
  }

  /// Start the foreground service and the filtered scan. Returns an error
  /// string if BLE is unavailable, else null.
  /// The adapter's actual state, not the plugin's cached snapshot.
  ///
  /// adapterStateNow is populated by the first event the plugin receives
  /// from the platform, so on a cold start it reports `unknown` even when
  /// Bluetooth is plainly on. Reading it directly made arming fail with
  /// "Turn Bluetooth on" until the user toggled Bluetooth off and on, which
  /// generated the event and populated the cache. That is exactly the
  /// symptom testers reported (field backlog #12).
  ///
  /// So: use the cache when it has a real answer, otherwise wait briefly on
  /// the stream for the first definite one, and fall back rather than hang
  /// if the platform never answers.
  static Future<BluetoothAdapterState> _adapterState() async {
    final cached = FlutterBluePlus.adapterStateNow;
    if (cached != BluetoothAdapterState.unknown) return cached;
    try {
      return await FlutterBluePlus.adapterState
          .firstWhere((s) => s != BluetoothAdapterState.unknown)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return FlutterBluePlus.adapterStateNow;
    }
  }

  Future<String?> arm() async {
    if (_armed) return null;
    if (await FlutterBluePlus.isSupported == false) {
      return 'Bluetooth is not supported on this device.';
    }
    if (await _adapterState() != BluetoothAdapterState.on) {
      return 'Turn Bluetooth on to arm the watch.';
    }

    try {
      await FlutterForegroundTask.startService(
        notificationTitle: 'Emergency watch active',
        notificationText: 'Watching for a nearby rescue drone.',
        callback: bleForegroundCallback,
      );
    } catch (_) {
      // Foreground service is best-effort; scanning can still run while
      // the app is open even if the service failed to start.
    }

    _scanSub = FlutterBluePlus.onScanResults.listen(_handleResults);
    // Filtering by service UUID is REQUIRED, not just an optimisation:
    // Android refuses unfiltered background scans while the screen is off,
    // and a locked phone is exactly our case. The module advertises this
    // UUID in its ADV packet so the filter can match it (see firmware).
    //
    // balanced, not lowPower: lowPower duty-cycles at roughly 10% and can
    // take tens of seconds to catch a 0.5-1 s advertiser. The foreground
    // service is already keeping us alive, so pay the small extra power
    // cost to alert someone in trouble promptly.
    await FlutterBluePlus.startScan(
      withServices: [_guid],
      continuousUpdates: true,
      androidScanMode: AndroidScanMode.balanced,
    );
    _armed = true;
    return null;
  }

  Future<void> disarm() async {
    if (!_armed) return;
    await _scanSub?.cancel();
    _scanSub = null;
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
    _armed = false;
    // Re-arming should alert immediately rather than sitting inside a
    // cooldown left over from the previous session.
    _lastNotified.clear();
  }

  /// How long before the SAME drone may raise another notification.
  /// A BLE scan re-reports an advertiser continuously (the aux module
  /// advertises every 0.5 to 1 s), so without this the phone fires a
  /// high-priority alert several times a second for as long as the victim
  /// stays in range. That is unusable, and worse, it trains people to
  /// dismiss the one notification that matters.
  static const Duration renotifyAfter = Duration(minutes: 5);

  /// Last time we alerted for each node id.
  final Map<String, DateTime> _lastNotified = {};

  void _handleResults(List<ScanResult> results) {
    for (final r in results) {
      final sighting = parseSighting(r);
      if (sighting == null) continue;

      // The sighting itself is always reported to the app: the UI should
      // update live. Only the NOTIFICATION is rate limited.
      onSighting?.call(sighting);

      if (!shouldNotify(sighting.nodeLabel, DateTime.now())) continue;
      NotificationService.showDroneFound(sighting.nodeLabel, sighting.ssid);
    }
  }

  /// Should this sighting raise a notification? Records the decision, so
  /// calling it twice in quick succession answers true then false.
  ///
  /// Pure apart from its own bookkeeping, and public, so the anti-spam rule
  /// can be unit tested without a radio (same approach as parseSighting).
  bool shouldNotify(String nodeLabel, DateTime now) {
    final last = _lastNotified[nodeLabel];
    if (last != null && now.difference(last) < renotifyAfter) return false;
    _lastNotified[nodeLabel] = now;
    return true;
  }

  /// Forget the notification history, so disarming and re-arming alerts
  /// again immediately rather than staying silent for the cooldown.
  @visibleForTesting
  void resetNotificationHistory() => _lastNotified.clear();

  /// Extract `nodeId|ssid` from the aux module's service data, else null.
  /// Public and pure so it can be unit tested without a radio.
  DroneSighting? parseSighting(ScanResult r) {
    final data = r.advertisementData.serviceData[_guid];
    if (data == null || data.isEmpty) return null;
    final payload = String.fromCharCodes(data);
    final parts = payload.split('|');
    if (parts.length < 2) return null;
    return DroneSighting(
      nodeLabel: parts[0],
      ssid: parts[1],
      rssi: r.rssi,
      seenAt: DateTime.now(),
    );
  }

  /// Test seam: parse from raw service-data bytes.
  static DroneSighting? parsePayloadBytes(List<int> bytes, {int rssi = -60}) {
    if (bytes.isEmpty) return null;
    final parts = String.fromCharCodes(bytes).split('|');
    if (parts.length < 2) return null;
    return DroneSighting(
      nodeLabel: parts[0],
      ssid: parts[1],
      rssi: rssi,
      seenAt: DateTime.now(),
    );
  }
}
