import 'package:dart_mavlink/mavlink.dart';
// The dialect also declares a CopterMode; we use our own from mav_service.
import 'package:dart_mavlink/dialects/ardupilotmega.dart' hide CopterMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/mavlink/mav_service.dart';

/// Serialize a message to bytes then parse it back, the way it would travel
/// over UDP to and from the flight controller.
Future<MavlinkFrame> roundTrip(MavlinkMessage message) async {
  final parser = MavlinkParser(MavlinkDialectArdupilotmega());
  final frame = MavlinkFrame.v2(0, 1, 1, message);
  final result = parser.stream.first;
  parser.parse(frame.serialize());
  return result;
}

void main() {
  group('MAVLink wire format (proves the library + our field mapping)', () {
    test('heartbeat round-trips and the armed bit decodes', () async {
      final frame = await roundTrip(Heartbeat(
        customMode: CopterMode.guided,
        type: mavTypeQuadrotor,
        autopilot: mavAutopilotArdupilotmega,
        baseMode: mavModeFlagSafetyArmed | mavModeFlagCustomModeEnabled,
        systemStatus: mavStateActive,
        mavlinkVersion: 3,
      ));
      expect(frame.message, isA<Heartbeat>());
      final hb = frame.message as Heartbeat;
      expect(hb.baseMode & mavModeFlagSafetyArmed, isNonZero);
      expect(hb.customMode, CopterMode.guided);
    });

    test('arm command encodes as COMMAND_LONG 400 param1=1', () async {
      // This is exactly what MavService.arm() builds.
      final frame = await roundTrip(CommandLong(
        param1: 1, param2: 0, param3: 0, param4: 0,
        param5: 0, param6: 0, param7: 0,
        command: mavCmdComponentArmDisarm,
        targetSystem: 1, targetComponent: 1, confirmation: 0,
      ));
      final cmd = frame.message as CommandLong;
      expect(cmd.command, 400);
      expect(cmd.param1, 1);
    });

    test('force-disarm carries the 21196 magic in param2', () async {
      final frame = await roundTrip(CommandLong(
        param1: 0, param2: 21196, param3: 0, param4: 0,
        param5: 0, param6: 0, param7: 0,
        command: mavCmdComponentArmDisarm,
        targetSystem: 1, targetComponent: 1, confirmation: 0,
      ));
      final cmd = frame.message as CommandLong;
      expect(cmd.param1, 0);
      expect(cmd.param2, 21196);
    });

    test('motor test encodes as DO_MOTOR_TEST 209', () async {
      final frame = await roundTrip(CommandLong(
        param1: 1, param2: 0, param3: 8, param4: 3,
        param5: 0, param6: 0, param7: 0,
        command: mavCmdDoMotorTest,
        targetSystem: 1, targetComponent: 1, confirmation: 0,
      ));
      final cmd = frame.message as CommandLong;
      expect(cmd.command, 209);
      expect(cmd.param3, 8); // throttle percent
    });

    // M7f fleet-deploy commands.

    test('takeoff encodes as NAV_TAKEOFF 22 with altitude in param7', () async {
      // This is exactly what MavService.takeoff(30) builds.
      final frame = await roundTrip(CommandLong(
        param1: 0, param2: 0, param3: 0, param4: 0,
        param5: 0, param6: 0, param7: 30,
        command: mavCmdNavTakeoff,
        targetSystem: 1, targetComponent: 1, confirmation: 0,
      ));
      final cmd = frame.message as CommandLong;
      expect(cmd.command, 22);
      expect(cmd.param7, 30); // takeoff altitude (m)
    });

    test('reposition encodes as DO_REPOSITION 192 with lat/lon as int32 1e7',
        () async {
      // This is exactly what MavService.gotoLocation(6.9271, 79.8612, 30)
      // builds: COMMAND_INT so lat/lon keep int precision a float cannot.
      final frame = await roundTrip(CommandInt(
        param1: -1, param2: 0, param3: 0, param4: double.nan,
        x: (6.9271 * 1e7).round(),
        y: (79.8612 * 1e7).round(),
        z: 30,
        command: mavCmdDoReposition,
        targetSystem: 1, targetComponent: 1,
        frame: mavFrameGlobalRelativeAlt,
        current: 0, autocontinue: 0,
      ));
      final cmd = frame.message as CommandInt;
      expect(cmd.command, 192);
      expect(cmd.x, 69271000);
      expect(cmd.y, 798612000);
      expect(cmd.z, 30);
      expect(cmd.frame, mavFrameGlobalRelativeAlt);
    });

    test('return to launch encodes as NAV_RETURN_TO_LAUNCH 20', () async {
      // This is exactly what MavService.returnToLaunch() builds (the recall
      // button AND the fleet battery watchdog).
      final frame = await roundTrip(CommandLong(
        param1: 0, param2: 0, param3: 0, param4: 0,
        param5: 0, param6: 0, param7: 0,
        command: mavCmdNavReturnToLaunch,
        targetSystem: 1, targetComponent: 1, confirmation: 0,
      ));
      final cmd = frame.message as CommandLong;
      expect(cmd.command, 20);
    });
  });

  group('STATUSTEXT chunk reassembly (field bug: garbled FC messages)', () {
    /// The FC text field is 50 chars. ArduPilot splits anything longer into
    /// chunks sharing one id, and we used to print each chunk as its own
    /// line, so the Flight controller messages panel showed orphaned tails
    /// like "(xy diff:110 > 100)" with no idea which check they came from.
    List<int> pad(String t) {
      final c = t.codeUnits.toList();
      while (c.length < 50) {
        c.add(0);
      }
      return c.take(50).toList();
    }

    /// A chunk that fills all 50 chars with no terminator: more is coming.
    List<int> full(String t) {
      assert(t.length == 50);
      return t.codeUnits.toList();
    }

    Statustext st(String text, {int id = 0, int seq = 0, bool fill = false}) =>
        Statustext(
          severity: mavSeverityWarning,
          text: fill ? full(text) : pad(text),
          id: id,
          chunkSeq: seq,
        );

    test('an unchunked message (id 0) is emitted as-is', () async {
      final svc = MavService();
      final seen = <String>[];
      svc.onStatusText.listen((s) => seen.add(s.text));
      svc.ingest(MavlinkFrame.v2(0, 1, 1, st('PreArm: Battery failsafe')));
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['PreArm: Battery failsafe']);
      svc.dispose();
    });

    test('a split message is joined into ONE line, not two fragments',
        () async {
      final svc = MavService();
      final seen = <String>[];
      svc.onStatusText.listen((s) => seen.add(s.text));
      // 50 chars exactly, then the tail: the shape that produced the bug.
      const head = 'PreArm: Check mag field for the primary compass an';
      svc.ingest(
          MavlinkFrame.v2(0, 1, 1, st(head, id: 7, seq: 0, fill: true)));
      svc.ingest(
          MavlinkFrame.v2(0, 1, 1, st('d (xy diff:110 > 100)', id: 7, seq: 1)));
      await Future<void>.delayed(Duration.zero);
      expect(seen.length, 1, reason: 'chunks must not appear as separate lines');
      expect(seen.single, '${head}d (xy diff:110 > 100)');
      svc.dispose();
    });

    test('chunks arriving out of order still join in sequence order',
        () async {
      final svc = MavService();
      final seen = <String>[];
      svc.onStatusText.listen((s) => seen.add(s.text));
      const head = 'PreArm: Check mag field for the primary compass an';
      // UDP: the tail overtakes the head.
      svc.ingest(
          MavlinkFrame.v2(0, 1, 1, st('d (xy diff:110 > 100)', id: 9, seq: 1)));
      svc.ingest(
          MavlinkFrame.v2(0, 1, 1, st(head, id: 9, seq: 0, fill: true)));
      await Future<void>.delayed(Duration.zero);
      expect(seen.single, '${head}d (xy diff:110 > 100)');
      svc.dispose();
    });

    test('two interleaved messages stay separate, keyed by id', () async {
      final svc = MavService();
      final seen = <String>[];
      svc.onStatusText.listen((s) => seen.add(s.text));
      svc.ingest(MavlinkFrame.v2(0, 1, 1, st('AAAA', id: 1, seq: 0)));
      svc.ingest(MavlinkFrame.v2(0, 1, 1, st('BBBB', id: 2, seq: 0)));
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['AAAA', 'BBBB']);
      svc.dispose();
    });
  });

  group('Telemetry decode + heartbeat gate', () {
    test('no heartbeat means the link is not fresh (commands disabled)', () {
      final svc = MavService();
      expect(svc.linkFresh, isFalse);
      expect(svc.sinceHeartbeat, isNull);
      svc.dispose();
    });

    test('a heartbeat makes the link fresh and sets armed + mode', () {
      final svc = MavService();
      svc.ingest(MavlinkFrame.v2(0, 1, 1, Heartbeat(
        customMode: CopterMode.stabilize,
        type: mavTypeQuadrotor,
        autopilot: mavAutopilotArdupilotmega,
        baseMode: mavModeFlagSafetyArmed,
        systemStatus: mavStateStandby,
        mavlinkVersion: 3,
      )));
      expect(svc.linkFresh, isTrue);
      expect(svc.telemetry.armed, isTrue);
      expect(svc.telemetry.modeName, 'STABILIZE');
      svc.dispose();
    });

    test('GPS + battery + position decode into telemetry', () {
      final svc = MavService();
      svc.ingest(MavlinkFrame.v2(0, 1, 1, GpsRawInt(
        timeUsec: 0, lat: 69271000, lon: 798612000, alt: 0, eph: 0, epv: 0,
        vel: 0, cog: 0, fixType: 3, satellitesVisible: 9,
        altEllipsoid: 0, hAcc: 0, vAcc: 0, velAcc: 0, hdgAcc: 0, yaw: 0,
      )));
      svc.ingest(MavlinkFrame.v2(0, 1, 1, SysStatus(
        onboardControlSensorsPresent: 0, onboardControlSensorsEnabled: 0,
        onboardControlSensorsHealth: 0, load: 0,
        voltageBattery: 11100, currentBattery: 0, dropRateComm: 0,
        errorsComm: 0, errorsCount1: 0, errorsCount2: 0, errorsCount3: 0,
        errorsCount4: 0, batteryRemaining: 87,
        onboardControlSensorsPresentExtended: 0,
        onboardControlSensorsEnabledExtended: 0,
        onboardControlSensorsHealthExtended: 0,
      )));
      expect(svc.telemetry.hasGpsFix, isTrue);
      expect(svc.telemetry.satellites, 9);
      expect(svc.telemetry.batteryVolts, closeTo(11.1, 0.001));
      expect(svc.telemetry.batteryRemaining, 87);
      svc.dispose();
    });
  });
}
