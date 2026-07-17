/// DroneController: ChangeNotifier bridge between the MAVLink service and
/// the Drone Control screen (file 04 / file 08). Holds connection state,
/// the latest telemetry, a short log of flight-controller status texts, and
/// the last command result. Refreshes on a 1 s tick so the heartbeat-age
/// display and the command gate stay live even between MAVLink packets.
library;

import 'dart:async';

import 'package:dart_mavlink/dialects/ardupilotmega.dart' show CommandAck;
import 'package:flutter/foundation.dart';

import '../mavlink/mav_service.dart';

class DroneController extends ChangeNotifier {
  final MavService _svc;
  Timer? _tick;
  final List<MavStatusText> statusLog = [];
  CommandAck? lastAck;
  DateTime? lastAckAt;
  String? connectError;

  DroneController([MavService? service]) : _svc = service ?? MavService() {
    _svc.onTelemetry.listen((_) => notifyListeners());
    _svc.onStatusText.listen((s) {
      statusLog.insert(0, s);
      if (statusLog.length > 40) statusLog.removeLast();
      notifyListeners();
    });
    _svc.onAck.listen((a) {
      lastAck = a;
      lastAckAt = DateTime.now();
      notifyListeners();
    });
  }

  Telemetry get telemetry => _svc.telemetry;
  bool get connected => _svc.connected;

  /// The single most important flag: true only while a heartbeat has arrived
  /// within the last 2 s. EVERY command control is gated on this.
  bool get linkFresh => _svc.linkFresh;
  Duration? get sinceHeartbeat => _svc.sinceHeartbeat;

  Future<void> connect(String target) async {
    connectError = null;
    try {
      await _svc.connect(target);
    } catch (e) {
      connectError = 'Could not open the link: $e. Are you on the drone Wi-Fi?';
    }
    // Start the liveness tick so the age display and gate update every second.
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
  }

  Future<void> disconnect() async {
    _tick?.cancel();
    _tick = null;
    await _svc.disconnect();
    notifyListeners();
  }

  // Commands. The screen only calls these when linkFresh is true (except
  // force-disarm, which must always be reachable as the kill switch).
  void arm() => _svc.arm();
  void disarm() => _svc.disarm();
  void forceDisarm() => _svc.disarm(force: true);
  void motorTest(int motor, {double throttlePct = 8, double seconds = 3}) =>
      _svc.motorTest(motor, throttlePct: throttlePct, seconds: seconds);
  void setMode(int mode) => _svc.setMode(mode);
  void land() => _svc.land();
  void returnToLaunch() => _svc.returnToLaunch();

  @override
  void dispose() {
    _tick?.cancel();
    _svc.dispose();
    super.dispose();
  }
}
