/// AppController: the single ChangeNotifier the UI watches. Coordinates
/// storage, the BLE watch, background logging, and uploads (file 06).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants.dart';
import '../models/stored_point.dart';
import '../services/ble_watch_service.dart';
import '../services/location_logger.dart';
import '../services/storage_service.dart';
import '../services/upload_service.dart';

class AppController extends ChangeNotifier {
  final StorageService storage;
  final BleWatchService watch;
  late final UploadService uploader;

  String deviceId = '';
  bool armed = false;
  bool loggingEnabled = true;
  bool emergencyMode = false;
  bool onboarded = false;
  List<StoredPoint> points = [];
  DroneSighting? lastSighting;
  bool onDrone = false;

  /// Which node we are connected to right now (e.g. "DRONE_A"), or null.
  String? connectedNodeId;

  Timer? _connTimer;
  bool _probing = false;

  AppController({StorageService? storage, BleWatchService? watch})
      : storage = storage ?? StorageService(),
        watch = watch ?? BleWatchService() {
    uploader = UploadService(this.storage);
    this.watch.onSighting = _onSighting;
  }

  Future<void> load() async {
    deviceId = await storage.deviceId();
    loggingEnabled = await storage.loggingEnabled();
    emergencyMode = await storage.emergencyMode();
    onboarded = await storage.onboarded();
    armed = watch.isArmed;
    points = await storage.points();
    notifyListeners();
    // Watch connectivity continuously so the SOS button lights up within
    // seconds of joining a drone AP by ANY route, not only through the BLE
    // notification flow (bench finding 2026-07-14: joining Wi-Fi manually
    // left SOS permanently greyed out because onDrone was checked once).
    startConnectivityWatch();
  }

  void startConnectivityWatch() {
    _connTimer?.cancel();
    _connTimer = Timer.periodic(
        const Duration(seconds: 4), (_) => checkOnDrone());
    checkOnDrone();
  }

  void stopConnectivityWatch() {
    _connTimer?.cancel();
    _connTimer = null;
  }

  Future<void> refreshPoints() async {
    points = await storage.points();
    notifyListeners();
  }

  void _onSighting(DroneSighting sighting) {
    lastSighting = sighting;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await storage.setOnboarded(true);
    onboarded = true;
    notifyListeners();
  }

  Future<String?> arm() async {
    final err = await watch.arm();
    armed = watch.isArmed;
    await storage.setArmed(armed);
    notifyListeners();
    return err;
  }

  Future<void> disarm() async {
    await watch.disarm();
    armed = watch.isArmed;
    await storage.setArmed(armed);
    notifyListeners();
  }

  Future<void> setLogging(bool value) async {
    loggingEnabled = value;
    await storage.setLoggingEnabled(value);
    if (value) {
      await LocationLogger.schedule();
    } else {
      await LocationLogger.cancel();
    }
    notifyListeners();
  }

  Future<void> setEmergencyMode(bool value) async {
    emergencyMode = value;
    await storage.setEmergencyMode(value);
    notifyListeners();
  }

  /// Manual "log a point now" (also drives the shortened-interval
  /// verification, file 06 acceptance 3).
  Future<StoredPoint?> logNow() async {
    final p = await LocationLogger.logNow();
    await refreshPoints();
    return p;
  }

  Future<void> deleteAllData() async {
    await storage.deleteAllData();
    await refreshPoints();
  }

  Future<void> setDisplayName(String name) => storage.setDisplayName(name);

  Future<String> displayName() => storage.displayName();

  /// Check whether we are currently on a drone AP (drives the SOS button
  /// and the connected flow). Guarded so overlapping ticks cannot pile up
  /// when the probe is slow (e.g. not connected, waiting to time out).
  Future<bool> checkOnDrone() async {
    if (_probing) return onDrone;
    _probing = true;
    try {
      final node = await uploader.connectedNodeId();
      final changed = node != connectedNodeId;
      connectedNodeId = node;
      onDrone = node != null;
      if (changed) notifyListeners();
    } finally {
      _probing = false;
    }
    return onDrone;
  }

  Future<UploadResult> uploadStored() => uploader.upload();

  Future<UploadResult> sendSos(String text) =>
      uploader.upload(sos: true, sosText: text);

  int get pendingUploadCount => points.where((p) => !p.uploaded).length;

  int get maxPoints => kMaxStoredPoints;

  @override
  void dispose() {
    stopConnectivityWatch();
    super.dispose();
  }
}
