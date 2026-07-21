import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/fleet_state.dart';

// A short leg: home near a target ~330 m north, so the demo sim reaches
// station in a few stepped ticks at 8 m/s.
const homeLat = 6.9000, homeLon = 79.8600;
const targetLat = 6.9030, homeToTargetLon = 79.8600;

DeployedDrone _deploy(FleetState f,
        {String label = 'd1', String source = 'brand', double? batteryWh}) =>
    f.deploy(
      label: label,
      source: source,
      real: false,
      homeLat: homeLat,
      homeLon: homeLon,
      targetLat: targetLat,
      targetLon: homeToTargetLon,
      role: 'user_ap',
      radiusM: 300,
      batteryWh: batteryWh,
    );

void main() {
  test('demo drone flies to station then is recalled home and lands', () {
    final f = FleetState();
    final d = _deploy(f);
    expect(d.phase, FleetPhase.enroute);

    // Step until it reaches station (each step = 20 simulated seconds).
    for (var i = 0; i < 20 && d.phase != FleetPhase.onStation; i++) {
      f.stepForTest(20);
    }
    expect(d.phase, FleetPhase.onStation);
    expect(d.distanceToTargetM, lessThan(f.arriveThresholdM));

    f.recall(d);
    expect(d.phase, FleetPhase.returning);
    for (var i = 0; i < 20 && d.phase != FleetPhase.landed; i++) {
      f.stepForTest(20);
    }
    expect(d.phase, FleetPhase.landed);
    expect(d.phase.releasesSlot, isTrue);
    f.dispose();
  });

  test('battery reserve auto-returns the drone before it dies', () {
    final f = FleetState()
      ..cruiseSpeedMs = 8
      ..avgPowerW = 150;
    // Far station (~5.5 km) and an endurance too short for a round trip, so
    // the reserve rule MUST turn the drone back partway out.
    final d = f.deploy(
      label: 'far', source: 'brand', real: false,
      homeLat: homeLat, homeLon: homeLon,
      targetLat: homeLat + 0.05, targetLon: homeLon,
      role: 'user_ap', radiusM: 300,
      batteryWh: 29, // ~700 s endurance vs ~1370 s round trip
    );

    var turnedBackWithCharge = false;
    for (var i = 0; i < 200 && d.phase != FleetPhase.landed; i++) {
      f.stepForTest(10);
      if (d.phase == FleetPhase.returning && d.batteryPct > 0) {
        turnedBackWithCharge = true;
      }
    }
    // It turned for home while it still had charge, and never stranded.
    expect(turnedBackWithCharge, isTrue,
        reason: 'low battery must trigger auto-return before depletion');
    f.dispose();
  });

  test('reserve percent grows with distance from home', () {
    final f = FleetState();
    final near = DeployedDrone(
      label: 'near', source: 'brand', real: false,
      homeLat: 0, homeLon: 0, targetLat: 0, targetLon: 0,
      role: 'user_ap', radiusM: 100, enduranceS: 600,
      startLat: 0.0005, startLon: 0, // ~55 m from home
    );
    final far = DeployedDrone(
      label: 'far', source: 'brand', real: false,
      homeLat: 0, homeLon: 0, targetLat: 0, targetLon: 0,
      role: 'user_ap', radiusM: 100, enduranceS: 600,
      startLat: 0.02, startLon: 0, // ~2.2 km from home
    );
    expect(f.reservePct(far), greaterThan(f.reservePct(near)));
    f.dispose();
  });

  test('inventory accounting: busy while deployed, freed on landing', () {
    final f = FleetState();
    final d = _deploy(f, label: 'relay-1');
    expect(f.busyLabels, contains('relay-1'));
    expect(f.inFlightCount, 1);

    f.recall(d);
    for (var i = 0; i < 40 && d.phase != FleetPhase.landed; i++) {
      f.stepForTest(20);
    }
    expect(d.phase, FleetPhase.landed);
    expect(f.busyLabels, isNot(contains('relay-1')));
    expect(f.inFlightCount, 0);
    f.dispose();
  });

  test('volunteer drone is pilot-advisory and still simulated', () {
    final f = FleetState();
    final d = _deploy(f, source: 'volunteer');
    expect(d.pilotAdvisory, isTrue);
    expect(d.note, contains('pilot'));
    f.dispose();
  });

  test('real drone: battery watchdog issues recall via callback', () {
    var recalls = 0;
    final f = FleetState(onRealRecall: (_) => recalls++);
    final d = f.deploy(
      label: 'DRONE_S', source: 'brand', real: true,
      homeLat: homeLat, homeLon: homeLon,
      targetLat: targetLat, targetLon: homeToTargetLon,
      role: 'system_drone', radiusM: 300,
    );
    expect(d.phase, FleetPhase.launchRequested);

    // Armed heartbeat: transition to enroute. Healthy battery: no recall.
    f.updateReal('DRONE_S', batteryVolts: 11.7, cellCount: 3, armed: true);
    expect(d.phase, FleetPhase.enroute);
    expect(recalls, 0);

    // Below 3.5 V/cell (3S): watchdog fires exactly one recall.
    f.updateReal('DRONE_S', batteryVolts: 10.2, cellCount: 3, armed: true);
    expect(d.phase, FleetPhase.returning);
    expect(recalls, 1);
    f.dispose();
  });

  test('real drone is not moved by the demo simulator', () {
    final f = FleetState();
    final d = f.deploy(
      label: 'DRONE_S', source: 'brand', real: true,
      homeLat: homeLat, homeLon: homeLon,
      targetLat: targetLat, targetLon: homeToTargetLon,
      role: 'system_drone', radiusM: 300,
    );
    final lat0 = d.curLat, lon0 = d.curLon;
    f.stepForTest(60);
    expect(d.curLat, lat0);
    expect(d.curLon, lon0);
    f.dispose();
  });

  test('signal loss shows FALLBACK, then LOST after the timeout', () {
    final f = FleetState()..lostAfter = Duration.zero;
    final d = _deploy(f);
    f.simulateSignalLoss(d);
    expect(d.phase, FleetPhase.fallback);
    // With a zero LOST timeout, the next tick escalates to LOST.
    f.stepForTest(1);
    expect(d.phase, FleetPhase.lost);
    // A lost drone keeps its slot (cannot be silently reused).
    expect(f.busyLabels, contains('d1'));
    f.dispose();
  });
}
