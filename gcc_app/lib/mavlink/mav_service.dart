/// MavService: the GCC's MAVLink link to the system drone's flight
/// controller (file 04 Drone Control, file 08).
///
/// Transport is UDP over whatever Wi-Fi the laptop is on. DRONE_S is now a
/// full mesh node: its Pi connects to the CC3D over USB and runs
/// mavlink_gateway (serial<->UDP), so the GCC reaches the FC either
/// DIRECTLY on RESCUE_S (10.42.0.1:14550) or RELAYED through a volunteer
/// node over the mesh (10.99.0.3:14550). Both are live MAVLink, never DTN
/// store-and-forward. See docs/DRONE_LINK.md.
///
/// Safety model (file 04 / file 08, non-negotiable):
///   - Every command button is gated on a MAVLink heartbeat fresher than
///     [staleAfter] (2 s). [linkFresh] drives that gate; the UI must honour
///     it. A dead link disables commands automatically.
///   - Commands are one-shot COMMAND_LONG with a CommandAck surfaced to the
///     operator; nothing is queued or retried blindly.
///   - This build targets PROPS-OFF ground testing. The headline action is
///     a motor test (spins a motor at low throttle on the bench), not an
///     armed takeoff.
library;

import 'dart:async';
import 'dart:io';

import 'package:dart_mavlink/mavlink.dart';
import 'package:dart_mavlink/dialects/ardupilotmega.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// ArduCopter custom flight-mode numbers (ArduPilot Copter mode enum).
class CopterMode {
  static const int stabilize = 0;
  static const int guided = 4;
  static const int loiter = 5;
  static const int rtl = 6;
  static const int land = 9;

  static const Map<int, String> names = {
    0: 'STABILIZE', 1: 'ACRO', 2: 'ALT_HOLD', 3: 'AUTO', 4: 'GUIDED',
    5: 'LOITER', 6: 'RTL', 7: 'CIRCLE', 9: 'LAND', 16: 'POSHOLD',
  };

  static String name(int mode) => names[mode] ?? 'MODE $mode';
}

/// Snapshot of what the FC is reporting, for the UI to render.
class Telemetry {
  bool armed = false;
  int customMode = 0;
  int systemStatus = 0;
  double? batteryVolts;
  int? batteryRemaining; // percent, -1 if unknown
  int gpsFixType = 0;
  int satellites = 0;
  double? lat;
  double? lon;
  double? relAltM;
  double rollDeg = 0;
  double pitchDeg = 0;
  double yawDeg = 0;

  String get modeName => CopterMode.name(customMode);
  bool get hasGpsFix => gpsFixType >= 3; // 3D fix
}

class MavStatusText {
  final int severity;
  final String text;
  final DateTime at;
  MavStatusText(this.severity, this.text) : at = DateTime.now();
}

class MavService {
  // GCS identity. 255 is the conventional ground-station system id.
  static const int gcsSystemId = 255;
  static const int gcsComponentId = 190; // MAV_COMP_ID_MISSIONPLANNER
  static const int targetSystem = 1; // the FC
  static const int targetComponent = 1;

  static const Duration staleAfter = Duration(seconds: 2);

  final _dialect = MavlinkDialectArdupilotmega();
  late final MavlinkParser _parser = MavlinkParser(_dialect);

  RawDatagramSocket? _socket;
  InternetAddress? _fcAddress;
  int _fcPort = 14550;
  int _seq = 0;

  Timer? _gcsHeartbeat;
  DateTime? _lastHeartbeat;

  final telemetry = Telemetry();

  final _telemetryCtrl = StreamController<Telemetry>.broadcast();
  final _statusCtrl = StreamController<MavStatusText>.broadcast();
  final _ackCtrl = StreamController<CommandAck>.broadcast();

  Stream<Telemetry> get onTelemetry => _telemetryCtrl.stream;
  Stream<MavStatusText> get onStatusText => _statusCtrl.stream;
  Stream<CommandAck> get onAck => _ackCtrl.stream;

  bool get connected => _socket != null;

  /// True only while a heartbeat has arrived within [staleAfter]. The UI
  /// MUST use this to enable/disable every command control.
  bool get linkFresh =>
      _lastHeartbeat != null &&
      DateTime.now().difference(_lastHeartbeat!) < staleAfter;

  Duration? get sinceHeartbeat => _lastHeartbeat == null
      ? null
      : DateTime.now().difference(_lastHeartbeat!);

  /// Connect to a MAVLink endpoint given as "host:port" or "udp:host:port".
  /// The laptop must already be joined to the drone's Wi-Fi.
  Future<void> connect(String target) async {
    await disconnect();
    final (host, port) = _parseTarget(target);
    _fcAddress = (await InternetAddress.lookup(host)).first;
    _fcPort = port;

    // Bind any local port; DroneBridge and mavlink-router both accept the
    // GCS as whatever source port it sends from.
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _socket!.listen(_onSocketEvent);

    _parser.stream.listen(_onFrame);

    // Send a GCS heartbeat every second so the FC sees a ground station
    // (needed for the GCS-loss failsafe and some arming paths).
    _gcsHeartbeat = Timer.periodic(
        const Duration(seconds: 1), (_) => _sendGcsHeartbeat());
    _sendGcsHeartbeat();
  }

  Future<void> disconnect() async {
    _gcsHeartbeat?.cancel();
    _gcsHeartbeat = null;
    _socket?.close();
    _socket = null;
    _lastHeartbeat = null;
  }

  static (String, int) _parseTarget(String target) {
    var t = target.trim();
    if (t.startsWith('udp:')) t = t.substring(4);
    final idx = t.lastIndexOf(':');
    if (idx < 0) return (t, 14550);
    final host = t.substring(0, idx);
    final port = int.tryParse(t.substring(idx + 1)) ?? 14550;
    return (host, port);
  }

  void _onSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;
    // DroneBridge sends from the FC; learn its address/port from the first
    // packet so replies go back to the right place even if we guessed.
    _fcAddress = dg.address;
    _fcPort = dg.port;
    _parser.parse(dg.data);
  }

  /// Test seam: feed a parsed frame as if it had arrived on the socket, so
  /// telemetry decode and the heartbeat gate can be tested without a radio.
  @visibleForTesting
  void ingest(MavlinkFrame frame) => _onFrame(frame);

  void _onFrame(MavlinkFrame frame) {
    final m = frame.message;
    if (m is Heartbeat) {
      _lastHeartbeat = DateTime.now();
      telemetry.armed = (m.baseMode & mavModeFlagSafetyArmed) != 0;
      telemetry.customMode = m.customMode;
      telemetry.systemStatus = m.systemStatus;
      _emit();
    } else if (m is SysStatus) {
      telemetry.batteryVolts =
          m.voltageBattery == 0xFFFF ? null : m.voltageBattery / 1000.0;
      telemetry.batteryRemaining = m.batteryRemaining;
      _emit();
    } else if (m is GpsRawInt) {
      telemetry.gpsFixType = m.fixType;
      telemetry.satellites = m.satellitesVisible;
      _emit();
    } else if (m is GlobalPositionInt) {
      telemetry.lat = m.lat / 1e7;
      telemetry.lon = m.lon / 1e7;
      telemetry.relAltM = m.relativeAlt / 1000.0;
      _emit();
    } else if (m is Attitude) {
      telemetry.rollDeg = m.roll * 180 / 3.14159265;
      telemetry.pitchDeg = m.pitch * 180 / 3.14159265;
      telemetry.yawDeg = m.yaw * 180 / 3.14159265;
      _emit();
    } else if (m is Statustext) {
      final text = String.fromCharCodes(
          m.text.takeWhile((c) => c != 0)).trim();
      if (text.isNotEmpty) _statusCtrl.add(MavStatusText(m.severity, text));
    } else if (m is CommandAck) {
      _ackCtrl.add(m);
    }
  }

  void _emit() {
    if (!_telemetryCtrl.isClosed) _telemetryCtrl.add(telemetry);
  }

  void _send(MavlinkMessage message) {
    final s = _socket;
    final addr = _fcAddress;
    if (s == null || addr == null) return;
    final frame = MavlinkFrame.v2(
        _seq++ & 0xFF, gcsSystemId, gcsComponentId, message);
    s.send(frame.serialize(), addr, _fcPort);
  }

  void _sendGcsHeartbeat() {
    _send(Heartbeat(
      customMode: 0,
      type: mavTypeGcs,
      autopilot: mavAutopilotInvalid,
      baseMode: 0,
      systemStatus: mavStateActive,
      mavlinkVersion: 3,
    ));
  }

  CommandLong _cmd(int command,
      {double p1 = 0, double p2 = 0, double p3 = 0, double p4 = 0,
      double p5 = 0, double p6 = 0, double p7 = 0}) {
    return CommandLong(
      param1: p1, param2: p2, param3: p3, param4: p4,
      param5: p5, param6: p6, param7: p7,
      command: command,
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      confirmation: 0,
    );
  }

  // --- commands (all guarded by the UI's linkFresh gate) --------------------

  /// Arm (props off for this phase). param2=0 = normal arming (checks apply).
  void arm() => _send(_cmd(mavCmdComponentArmDisarm, p1: 1));

  /// Disarm. force=true (param2=21196) is the emergency kill and always
  /// works; the always-visible DISARM button uses it.
  void disarm({bool force = false}) =>
      _send(_cmd(mavCmdComponentArmDisarm, p1: 0, p2: force ? 21196 : 0));

  /// Spin one motor at low throttle on the bench (PROPS OFF). This is the
  /// headline "the GCC turned the motors on" demo: safe, brief, one motor.
  /// motor: 1..4. throttlePct default 8%. seconds default 3.
  void motorTest(int motor, {double throttlePct = 8, double seconds = 3}) {
    _send(_cmd(mavCmdDoMotorTest,
        p1: motor.toDouble(),
        p2: 0, // MOTOR_TEST_THROTTLE_PERCENT
        p3: throttlePct,
        p4: seconds,
        p5: 0, // motor count (0 = just this one)
        p6: 0));
  }

  /// Set an ArduCopter flight mode via DO_SET_MODE.
  void setMode(int copterMode) {
    _send(_cmd(mavCmdDoSetMode,
        p1: mavModeFlagCustomModeEnabled.toDouble(),
        p2: copterMode.toDouble()));
  }

  /// Return to launch via the explicit NAV command (works from any mode on
  /// ArduCopter). Used by the RECALL button AND the fleet battery watchdog
  /// (M7f), so a low battery always sends the drone home. NOTE: the flight
  /// policy is unchanged, PROPS-OFF ground testing only; this is observed
  /// on the bench, not flown, until the operator clears free flight.
  void returnToLaunch() => _send(_cmd(mavCmdNavReturnToLaunch));

  void land() => setMode(CopterMode.land);

  /// Guided takeoff to [altM] metres. ArduCopter requires GUIDED + armed
  /// first; the fleet controller sequences setMode(guided) -> arm ->
  /// takeoff. Bench: with props off this is the command pipeline proof, the
  /// FC accepts and acks it, motors are not spun to flight.
  void takeoff(double altM) =>
      _send(_cmd(mavCmdNavTakeoff, p7: altM));

  /// Reposition to a lat/lon in GUIDED via DO_REPOSITION. Uses COMMAND_INT
  /// because lat/lon as degrees*1e7 need int32 precision a float param
  /// cannot hold. [altM] is above home (MAV_FRAME_GLOBAL_RELATIVE_ALT).
  void gotoLocation(double lat, double lon, double altM,
      {double groundSpeed = -1}) {
    _send(CommandInt(
      param1: groundSpeed, // -1 = use default speed
      param2: 0, // MAV_DO_REPOSITION_FLAGS
      param3: 0,
      param4: double.nan, // yaw: keep current heading
      x: (lat * 1e7).round(),
      y: (lon * 1e7).round(),
      z: altM,
      command: mavCmdDoReposition,
      targetSystem: targetSystem,
      targetComponent: targetComponent,
      frame: mavFrameGlobalRelativeAlt,
      current: 0,
      autocontinue: 0,
    ));
  }

  void dispose() {
    disconnect();
    _telemetryCtrl.close();
    _statusCtrl.close();
    _ackCtrl.close();
  }
}
