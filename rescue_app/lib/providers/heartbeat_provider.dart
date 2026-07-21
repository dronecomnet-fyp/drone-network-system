/// HeartbeatProvider (M7d): shares the rescuer's location with the mesh so
/// the ground control centre can see where teams are.
///
/// Battery-friendly by design: it only runs while the rescuer is logged in
/// AND the app is in the foreground, and only every 90 seconds. Nothing runs
/// in the background or when logged out. This is the honest tradeoff
/// (continuous background tracking is out of scope); the operator sees each
/// rescuer's LAST known position with its age.
///
/// Mirrors the message poller's single-shot self-rescheduling timer and its
/// adaptive backoff on failure, so a node going out of range does not cause
/// a retry storm.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

import '../services/api_service.dart';

class HeartbeatProvider with ChangeNotifier {
  static const _kEnabled = 'share_location';
  static const Duration _interval = Duration(seconds: 90);
  static const Duration _maxBackoff = Duration(minutes: 5);
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  HeartbeatProvider() {
    _load();
  }

  bool _enabled = true;
  bool _loggedIn = false;
  bool _foreground = true;
  Timer? _timer;
  Duration _backoff = _interval;

  DateTime? lastSentAt;
  String? lastError;

  bool get enabled => _enabled;
  DateTime? get lastSent => lastSentAt;
  String? get statusError => lastError;

  /// True when a beat can actually be sent right now.
  bool get active => _enabled && _loggedIn && _foreground;

  Future<void> _load() async {
    final saved = await _storage.read(key: _kEnabled);
    _enabled = saved == null || saved == 'true';
    notifyListeners();
    _reschedule(immediate: true);
  }

  Future<void> setEnabled({required bool value}) async {
    _enabled = value;
    await _storage.write(key: _kEnabled, value: value ? 'true' : 'false');
    notifyListeners();
    _reschedule(immediate: true);
  }

  /// Wired to AuthProvider: heartbeats only while a session exists.
  void setLoggedIn({required bool value}) {
    if (_loggedIn == value) {
      return;
    }
    _loggedIn = value;
    _reschedule(immediate: true);
  }

  /// Wired to the app lifecycle: paused in the background (battery).
  void setForeground({required bool value}) {
    if (_foreground == value) {
      return;
    }
    _foreground = value;
    _reschedule(immediate: value);
  }

  void _reschedule({bool immediate = false}) {
    _timer?.cancel();
    if (!active) {
      notifyListeners();
      return;
    }
    _timer = Timer(immediate ? Duration.zero : _backoff, _beat);
  }

  Future<void> _beat() async {
    if (!active) {
      return;
    }
    final pos = await _position();
    if (pos == null) {
      // No fix available: back off and try later, do not spam.
      _bumpBackoff();
      _reschedule();
      return;
    }
    try {
      await APIService.postLocation(
        pos.latitude,
        pos.longitude,
        accuracyM: pos.accuracy,
      );
      lastSentAt = DateTime.now();
      lastError = null;
      _backoff = _interval; // success: back to the normal cadence
    } catch (e) {
      lastError = e.toString();
      _bumpBackoff();
    }
    notifyListeners();
    _reschedule();
  }

  void _bumpBackoff() {
    final next = _backoff * 2;
    _backoff = next > _maxBackoff ? _maxBackoff : next;
  }

  /// Medium accuracy is enough to place a rescuer on the map and is far
  /// cheaper than a best-accuracy fix. Falls back to the last known
  /// position if a fresh fix times out.
  Future<Position?> _position() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return null;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        lastError = 'Location permission denied';
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
