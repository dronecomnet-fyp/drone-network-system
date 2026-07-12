/// StorageService: on-device state only (file 06 data design; privacy is
/// a selling point). Holds:
///   - a random device_id generated on first run (no phone number, no
///     name required); an optional display name for rescuers
///   - a ring buffer of the last kMaxStoredPoints location points
///   - user settings: logging on/off, emergency mode flag
///
/// Everything is stored via shared_preferences as JSON. Uninstall wipes
/// it (a fresh install therefore gets a new device_id and an empty log:
/// file 06 acceptance 4).
///
/// This class is used from BOTH the UI isolate and background isolates
/// (WorkManager location task), so every method reads/writes prefs fresh
/// rather than caching, and appendPoint re-reads before trimming to avoid
/// losing a point written by the other isolate.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../models/stored_point.dart';

class StorageService {
  static const _kDeviceId = 'device_id';
  static const _kDisplayName = 'display_name';
  static const _kPoints = 'stored_points';
  static const _kLoggingEnabled = 'logging_enabled';
  static const _kEmergencyMode = 'emergency_mode';
  static const _kArmed = 'watch_armed';
  static const _kOnboarded = 'onboarded';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String> deviceId() async {
    final p = await _prefs;
    var id = p.getString(_kDeviceId);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await p.setString(_kDeviceId, id);
    }
    return id;
  }

  Future<String> displayName() async =>
      (await _prefs).getString(_kDisplayName) ?? '';

  Future<void> setDisplayName(String name) async =>
      (await _prefs).setString(_kDisplayName, name.trim());

  Future<List<StoredPoint>> points() async {
    final raw = (await _prefs).getString(_kPoints);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => StoredPoint.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writePoints(List<StoredPoint> pts) async {
    final raw = jsonEncode(pts.map((e) => e.toJson()).toList());
    await (await _prefs).setString(_kPoints, raw);
  }

  /// Append one point and trim to the ring-buffer size (oldest dropped).
  /// Re-reads current points first so a UI-isolate write and a
  /// background-isolate write do not clobber each other.
  Future<void> appendPoint(StoredPoint point) async {
    final current = await points();
    current.add(point);
    while (current.length > kMaxStoredPoints) {
      current.removeAt(0);
    }
    await _writePoints(current);
  }

  /// Mark the given recorded_at timestamps as uploaded (file 06: mark
  /// uploaded_at locally after a successful /checkin).
  Future<void> markUploaded(Set<String> recordedAts) async {
    final current = await points();
    final updated = current
        .map((p) =>
            recordedAts.contains(p.recordedAt) ? p.copyWith(uploaded: true) : p)
        .toList();
    await _writePoints(updated);
  }

  Future<void> deleteAllData() async {
    final p = await _prefs;
    // Keep device_id? No: "delete all" should be a real reset. The
    // "Your data" screen documents that this clears the log; the device
    // id is regenerated lazily on next use.
    await p.remove(_kPoints);
  }

  Future<bool> loggingEnabled() async =>
      (await _prefs).getBool(_kLoggingEnabled) ?? true;

  Future<void> setLoggingEnabled(bool value) async =>
      (await _prefs).setBool(_kLoggingEnabled, value);

  Future<bool> emergencyMode() async =>
      (await _prefs).getBool(_kEmergencyMode) ?? false;

  Future<void> setEmergencyMode(bool value) async =>
      (await _prefs).setBool(_kEmergencyMode, value);

  Future<bool> armed() async => (await _prefs).getBool(_kArmed) ?? false;

  Future<void> setArmed(bool value) async =>
      (await _prefs).setBool(_kArmed, value);

  Future<bool> onboarded() async =>
      (await _prefs).getBool(_kOnboarded) ?? false;

  Future<void> setOnboarded(bool value) async =>
      (await _prefs).setBool(_kOnboarded, value);
}
