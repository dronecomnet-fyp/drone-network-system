/// FleetState (M7f): coordinates a whole operation's worth of drones from
/// one board, in two modes behind one UI.
///
/// Honest constraint (file 08 scope guard): only the system drone (DRONE_S)
/// has a flight controller the GCC commands over MAVLink. Volunteer drones
/// carry our comm module but their flight is their pilots' job. So this is
/// a fleet COORDINATION layer:
///
///   - DEMO mode: an exam-safe simulator advances each drone along its path,
///     drains a modelled battery, and AUTO-RETURNS it before the battery
///     dies (reserve = 1.5x the energy to fly home). Any number of drones.
///   - REAL mode (system drone only): the UI drives the actual MAVLink
///     sequence via DroneController; FleetState tracks its state and runs a
///     per-cell-voltage battery watchdog that issues RTL. Flight policy is
///     unchanged: PROPS-OFF bench verification only until the operator
///     clears free flight.
///
/// Pure Dart (no Flutter widgets, no MAVLink import) so the state machine
/// and reserve math are unit-testable with no hardware. REAL commands are
/// delivered through injected callbacks the UI wires to DroneController.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../services/geo.dart';

enum FleetPhase {
  planned,
  launchRequested,
  enroute,
  onStation,
  returning,
  landed,
  fallback, // only the LoRa fallback beacon still heard; position is stale
  lost, // nothing heard past the timeout
}

extension FleetPhaseLabel on FleetPhase {
  String get label {
    switch (this) {
      case FleetPhase.planned:
        return 'PLANNED';
      case FleetPhase.launchRequested:
        return 'LAUNCH REQUESTED';
      case FleetPhase.enroute:
        return 'ENROUTE';
      case FleetPhase.onStation:
        return 'ON STATION';
      case FleetPhase.returning:
        return 'RETURNING';
      case FleetPhase.landed:
        return 'LANDED';
      case FleetPhase.fallback:
        return 'FALLBACK (LoRa)';
      case FleetPhase.lost:
        return 'LOST';
    }
  }

  /// A drone still occupies its inventory slot until it lands.
  bool get releasesSlot => this == FleetPhase.landed;

  bool get isActive =>
      this == FleetPhase.enroute ||
      this == FleetPhase.onStation ||
      this == FleetPhase.launchRequested;
}

class DeployedDrone {
  final String label;
  final String source; // "brand" | "volunteer"
  final bool real; // true only for the system drone (MAVLink controllable)

  final double homeLat;
  final double homeLon;
  final double targetLat;
  final double targetLon;
  final String role;
  final double radiusM;

  double curLat;
  double curLon;
  double batteryPct;
  FleetPhase phase;

  /// Modelled flight endurance at full battery (DEMO), seconds.
  final double enduranceS;

  /// Last time a real drone reported telemetry (REAL only), for the
  /// FALLBACK / LOST escalation.
  DateTime lastHeard;

  /// A volunteer drone is advisory: the GCC shows the pilot an instruction
  /// rather than commanding flight. Used for the board's wording only.
  bool get pilotAdvisory => source == 'volunteer';

  String note = '';

  DeployedDrone({
    required this.label,
    required this.source,
    required this.real,
    required this.homeLat,
    required this.homeLon,
    required this.targetLat,
    required this.targetLon,
    required this.role,
    required this.radiusM,
    required this.enduranceS,
    double? startLat,
    double? startLon,
    this.batteryPct = 100,
    this.phase = FleetPhase.launchRequested,
  })  : curLat = startLat ?? homeLat,
        curLon = startLon ?? homeLon,
        lastHeard = DateTime.now();

  double get distanceToTargetM =>
      haversineM(curLat, curLon, targetLat, targetLon);
  double get distanceHomeM => haversineM(curLat, curLon, homeLat, homeLon);
}

class FleetState extends ChangeNotifier {
  // --- tunables (all documented, all overridable in Settings) -------------
  // Cruise speed: typical small multirotor cruise. Confidence: Low.
  double cruiseSpeedMs = 8.0;
  // Average electrical power in flight, for the endurance model. A small
  // 5-inch quad hovers around this. Confidence: Low.
  double avgPowerW = 150.0;
  // Endurance used when a drone has no battery_wh spec. Confidence: Low.
  double defaultEnduranceMin = 12.0;
  // Reserve safety factor on the energy needed to fly home. Confidence: Low.
  double reserveFactor = 1.5;
  // REAL battery watchdog: land-now LiPo threshold per cell. Standard LiPo
  // practice. Confidence: Moderate.
  double perCellThresholdV = 3.5;
  // DEMO wall-clock acceleration: simulated seconds per real second, so a
  // multi-minute flight is watchable in a demo.
  double simSpeed = 30.0;
  // Distance within which a leg counts as arrived.
  double arriveThresholdM = 15.0;
  // A real drone unheard for this long drops to FALLBACK, then LOST.
  Duration fallbackAfter = const Duration(seconds: 8);
  Duration lostAfter = const Duration(seconds: 30);

  bool demoMode = true;

  /// Called when a real (system) drone is deployed and when it is recalled,
  /// so the UI can drive the actual MAVLink sequence. Injected by the UI.
  final void Function(DeployedDrone drone)? onRealDeploy;
  final void Function(DeployedDrone drone)? onRealRecall;

  final List<DeployedDrone> deployed = [];
  Timer? _sim;

  FleetState({this.onRealDeploy, this.onRealRecall});

  // --- inventory accounting ----------------------------------------------

  /// Labels currently occupying a slot (deployed and not yet landed).
  Set<String> get busyLabels => deployed
      .where((d) => !d.phase.releasesSlot)
      .map((d) => d.label)
      .toSet();

  int get inFlightCount =>
      deployed.where((d) => !d.phase.releasesSlot).length;

  double _enduranceSeconds(double? batteryWh) {
    if (batteryWh == null || batteryWh <= 0 || avgPowerW <= 0) {
      return defaultEnduranceMin * 60;
    }
    return batteryWh / avgPowerW * 3600;
  }

  /// Battery percent below which the drone must turn for home now, given how
  /// far it currently is from home. This is the "bring them back before the
  /// battery dies" rule.
  double reservePct(DeployedDrone d) {
    if (d.enduranceS <= 0) return 0;
    final secondsHome = d.distanceHomeM / math.max(cruiseSpeedMs, 0.1);
    return (reserveFactor * secondsHome / d.enduranceS * 100).clamp(0, 100);
  }

  // --- deploy / recall ----------------------------------------------------

  DeployedDrone deploy({
    required String label,
    required String source,
    required bool real,
    required double homeLat,
    required double homeLon,
    required double targetLat,
    required double targetLon,
    required String role,
    required double radiusM,
    double? batteryWh,
  }) {
    final d = DeployedDrone(
      label: label,
      source: source,
      real: real,
      homeLat: homeLat,
      homeLon: homeLon,
      targetLat: targetLat,
      targetLon: targetLon,
      role: role,
      radiusM: radiusM,
      enduranceS: _enduranceSeconds(batteryWh),
      phase: FleetPhase.launchRequested,
    );
    d.note = real
        ? 'system drone: MAVLink deploy (bench, props off)'
        : (d.pilotAdvisory
            ? 'advise pilot to launch toward station'
            : 'demo drone launching');
    deployed.add(d);
    if (real) {
      // A real drone is driven by its own telemetry (updateReal), never the
      // simulator; it stays LAUNCH_REQUESTED until an armed heartbeat.
      onRealDeploy?.call(d);
    } else {
      d.phase = FleetPhase.enroute;
    }
    _ensureSim();
    notifyListeners();
    return d;
  }

  void recall(DeployedDrone d) {
    if (d.phase == FleetPhase.landed || d.phase == FleetPhase.lost) return;
    d.phase = FleetPhase.returning;
    d.note = d.pilotAdvisory ? 'advise pilot to return home' : 'returning home';
    if (d.real) onRealRecall?.call(d);
    notifyListeners();
  }

  void recallAll() {
    for (final d in deployed) {
      recall(d);
    }
  }

  void remove(DeployedDrone d) {
    deployed.remove(d);
    if (deployed.isEmpty) _stopSim();
    notifyListeners();
  }

  void clearLanded() {
    deployed.removeWhere(
        (d) => d.phase == FleetPhase.landed || d.phase == FleetPhase.lost);
    if (deployed.isEmpty) _stopSim();
    notifyListeners();
  }

  // --- REAL telemetry feed (system drone) ---------------------------------

  /// The UI pushes the system drone's live telemetry here each tick. Runs
  /// the per-cell battery watchdog and updates position/liveness.
  void updateReal(
    String label, {
    double? lat,
    double? lon,
    double? batteryVolts,
    int cellCount = 3,
    bool armed = false,
  }) {
    for (final d in deployed.where((d) => d.label == label && d.real)) {
      d.lastHeard = DateTime.now();
      if (lat != null && lon != null) {
        d.curLat = lat;
        d.curLon = lon;
      }
      if (d.phase == FleetPhase.launchRequested && armed) {
        d.phase = FleetPhase.enroute;
      }
      if (batteryVolts != null && cellCount > 0) {
        final perCell = batteryVolts / cellCount;
        if (perCell <= perCellThresholdV && d.phase.isActive) {
          d.note = 'battery watchdog: ${perCell.toStringAsFixed(2)} V/cell, RTL';
          recall(d);
        }
      }
      notifyListeners();
    }
  }

  // --- DEMO fault injection (to show the LoRa fallback story) --------------

  /// Simulate the drone's Pi/module going quiet: the only thing still heard
  /// is the aux LoRa fallback beacon, so the drone shows FALLBACK at its
  /// last position instead of vanishing.
  void simulateSignalLoss(DeployedDrone d) {
    if (d.phase == FleetPhase.landed) return;
    d.phase = FleetPhase.fallback;
    d.lastHeard = DateTime.now();
    d.note = 'Pi/module quiet, aux LoRa beacon at last position';
    notifyListeners();
  }

  // --- simulation loop ----------------------------------------------------

  void _ensureSim() {
    _sim ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stopSim() {
    _sim?.cancel();
    _sim = null;
  }

  /// One real second of simulation. Public for deterministic testing:
  /// [simSecondsOverride] injects the elapsed simulated time instead of
  /// [simSpeed], so tests are not wall-clock dependent.
  void stepForTest(double simSeconds) => _tick(simSecondsOverride: simSeconds);

  void _tick({double? simSecondsOverride}) {
    final simSeconds = simSecondsOverride ?? simSpeed;
    var changed = false;

    for (final d in deployed) {
      // FALLBACK -> LOST escalation for anything that went quiet.
      if (d.phase == FleetPhase.fallback) {
        if (DateTime.now().difference(d.lastHeard) >= lostAfter) {
          d.phase = FleetPhase.lost;
          d.note = 'no beacon past timeout';
          changed = true;
        }
        continue;
      }
      // Real drones move from their own telemetry, not the simulator.
      if (d.real) continue;
      if (d.phase == FleetPhase.landed || d.phase == FleetPhase.lost) continue;

      // Battery drain.
      if (d.enduranceS > 0) {
        d.batteryPct =
            (d.batteryPct - simSeconds / d.enduranceS * 100).clamp(0, 100);
      }

      // Auto-return before the battery dies.
      if (d.phase != FleetPhase.returning &&
          d.batteryPct <= reservePct(d)) {
        d.phase = FleetPhase.returning;
        d.note = d.pilotAdvisory
            ? 'low battery: advise pilot to return'
            : 'low battery: auto-returning';
        changed = true;
      }

      final dest = d.phase == FleetPhase.returning
          ? [d.homeLat, d.homeLon]
          : [d.targetLat, d.targetLon];
      final moved = _stepToward(d, dest[0], dest[1], simSeconds);
      changed = changed || moved;

      // Arrivals.
      if (d.phase == FleetPhase.returning &&
          d.distanceHomeM <= arriveThresholdM) {
        d.phase = FleetPhase.landed;
        d.note = 'landed, slot freed';
        changed = true;
      } else if ((d.phase == FleetPhase.enroute ||
              d.phase == FleetPhase.launchRequested) &&
          d.distanceToTargetM <= arriveThresholdM) {
        d.phase = FleetPhase.onStation;
        d.note = d.pilotAdvisory ? 'pilot on station' : 'holding station';
        changed = true;
      } else if (d.phase == FleetPhase.launchRequested) {
        d.phase = FleetPhase.enroute;
        changed = true;
      }
    }

    if (deployed.every(
        (d) => d.phase == FleetPhase.landed || d.phase == FleetPhase.lost)) {
      _stopSim();
    }
    if (changed) notifyListeners();
  }

  /// Move [d] toward (lat,lon) by cruiseSpeed*simSeconds metres, linearly
  /// in the lat/lon plane (fine at operation scale). Returns true if moved.
  bool _stepToward(DeployedDrone d, double lat, double lon, double simSeconds) {
    final dist = haversineM(d.curLat, d.curLon, lat, lon);
    if (dist <= arriveThresholdM) return false;
    final step = cruiseSpeedMs * simSeconds;
    final frac = (step / dist).clamp(0.0, 1.0);
    d.curLat += (lat - d.curLat) * frac;
    d.curLon += (lon - d.curLon) * frac;
    return true;
  }

  @override
  void dispose() {
    _stopSim();
    super.dispose();
  }
}
