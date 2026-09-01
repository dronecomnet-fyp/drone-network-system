/// MissionValidator: pure Dart service to validate mission and drone feasibility.
///
/// Validates whether a drone deployment or placement is technically feasible:
/// - One-way flight range (can the drone even reach the station?)
/// - Round-trip flight energy (can the drone return home before battery dies?)
/// - Reserve threshold (is there enough safety margin for headwind / climb?)
/// - Usable on-station coverage time (how long can it provide AP/relay service?)
/// - Spatial bounds (is the placement inside the mission operation area?)
/// - Spec certainty (are we using verified cached specs or conservative defaults?)
///
/// Pure Dart (no Flutter widgets) so it is 100% unit testable without device or UI.
library;

import 'dart:math' as math;

import '../state/mission_state.dart';
import 'geo.dart';

enum FeasibilityLevel {
  feasible,
  warning,
  impossible,
}

class FeasibilityMetrics {
  final double distanceHomeM;
  final double roundTripDistanceM;
  final double enduranceS;
  final double oneWayFlightTimeS;
  final double roundTripFlightTimeS;
  final double oneWayBatteryPct;
  final double roundTripBatteryPct;
  final double reserveBatteryPct;
  final double usableStationTimeS;
  final bool isInsideArea;
  final bool hasSpecs;
  final double maxOneWayRangeM;
  final double maxRoundTripRangeM;

  const FeasibilityMetrics({
    required this.distanceHomeM,
    required this.roundTripDistanceM,
    required this.enduranceS,
    required this.oneWayFlightTimeS,
    required this.roundTripFlightTimeS,
    required this.oneWayBatteryPct,
    required this.roundTripBatteryPct,
    required this.reserveBatteryPct,
    required this.usableStationTimeS,
    required this.isInsideArea,
    required this.hasSpecs,
    required this.maxOneWayRangeM,
    required this.maxRoundTripRangeM,
  });

  String get distanceKmFormatted => (distanceHomeM / 1000).toStringAsFixed(2);
  String get oneWayTimeFormatted => _formatSeconds(oneWayFlightTimeS);
  String get roundTripTimeFormatted => _formatSeconds(roundTripFlightTimeS);
  String get usableStationTimeFormatted => _formatSeconds(usableStationTimeS);
  String get maxRangeKmFormatted => (maxRoundTripRangeM / 1000).toStringAsFixed(2);

  static String _formatSeconds(double seconds) {
    if (seconds <= 0) return '0 min 0 s';
    final totalSec = seconds.round();
    final m = totalSec ~/ 60;
    final s = totalSec % 60;
    if (m == 0) return '${s}s';
    return '$m min ${s}s';
  }
}

class ValidationResult {
  final FeasibilityLevel level;
  final FeasibilityMetrics metrics;
  final List<String> errors;
  final List<String> warnings;
  final List<String> recommendations;

  const ValidationResult({
    required this.level,
    required this.metrics,
    required this.errors,
    required this.warnings,
    required this.recommendations,
  });

  bool get isImpossible => level == FeasibilityLevel.impossible;
  bool get isWarning => level == FeasibilityLevel.warning;
  bool get isFeasible => level == FeasibilityLevel.feasible;
}

class MissionValidator {
  /// Default cruising speed (m/s) if not overridden.
  static const double defaultCruiseSpeedMs = 8.0;

  /// Default average power consumption (Watts).
  static const double defaultAvgPowerW = 150.0;

  /// Default endurance in minutes if specs unknown.
  static const double defaultEnduranceMin = 12.0;

  /// Default safety factor for return trip (1.5x energy needed to fly home).
  static const double defaultReserveFactor = 1.5;

  /// Minimum on-station time (in seconds) below which a warning is issued.
  static const double minRecommendedStationTimeS = 120.0; // 2 minutes

  /// Validate a drone assignment to a placement.
  static ValidationResult validateDroneDeployment({
    required DroneResource drone,
    required DronePlacement placement,
    required MissionState mission,
    required double homeLat,
    required double homeLon,
    double cruiseSpeedMs = defaultCruiseSpeedMs,
    double avgPowerW = defaultAvgPowerW,
    double fallbackEnduranceMin = defaultEnduranceMin,
    double reserveFactor = defaultReserveFactor,
  }) {
    final specs = mission.specsFor(drone);
    final hasSpecs = specs?.batteryWh != null && specs!.batteryWh! > 0;

    final double enduranceS;
    if (hasSpecs && avgPowerW > 0) {
      enduranceS = (specs.batteryWh! / avgPowerW) * 3600;
    } else {
      enduranceS = fallbackEnduranceMin * 60;
    }

    final distanceM = haversineM(homeLat, homeLon, placement.lat, placement.lon);
    final roundTripDistM = distanceM * 2;
    final speed = math.max(cruiseSpeedMs, 0.1);

    final oneWayTimeS = distanceM / speed;
    final roundTripTimeS = roundTripDistM / speed;

    final oneWayBatteryPct = enduranceS > 0 ? (oneWayTimeS / enduranceS * 100) : 100.0;
    final roundTripBatteryPct = enduranceS > 0 ? (roundTripTimeS / enduranceS * 100) : 100.0;

    // Safety reserve required to fly home with safety factor
    final reserveBatteryPct = enduranceS > 0
        ? (reserveFactor * (distanceM / speed) / enduranceS * 100)
        : 100.0;

    // Total flight energy = one-way out + reserve for return
    final totalFlightNeededPct = oneWayBatteryPct + reserveBatteryPct;

    final remainingForStationPct = math.max(0.0, 100.0 - totalFlightNeededPct);
    final usableStationTimeS = (remainingForStationPct / 100.0) * enduranceS;

    final maxOneWayRangeM = enduranceS * speed;
    // Max safe round-trip distance allowing reserve
    final maxRoundTripRangeM = (enduranceS * speed) / (1.0 + reserveFactor);

    // Area polygon check
    final polygon = mission.area.map((p) => [p.lat, p.lon]).toList();
    final isInsideArea = polygon.length < 3 || pointInPolygon(placement.lat, placement.lon, polygon);

    final metrics = FeasibilityMetrics(
      distanceHomeM: distanceM,
      roundTripDistanceM: roundTripDistM,
      enduranceS: enduranceS,
      oneWayFlightTimeS: oneWayTimeS,
      roundTripFlightTimeS: roundTripTimeS,
      oneWayBatteryPct: oneWayBatteryPct,
      roundTripBatteryPct: roundTripBatteryPct,
      reserveBatteryPct: reserveBatteryPct,
      usableStationTimeS: usableStationTimeS,
      isInsideArea: isInsideArea,
      hasSpecs: hasSpecs,
      maxOneWayRangeM: maxOneWayRangeM,
      maxRoundTripRangeM: maxRoundTripRangeM,
    );

    final errors = <String>[];
    final warnings = <String>[];
    final recommendations = <String>[];

    // 1. One-way flight check (can drone even reach target?)
    if (oneWayBatteryPct >= 100.0 || distanceM > maxOneWayRangeM) {
      final deficitKm = ((distanceM - maxOneWayRangeM) / 1000).toStringAsFixed(2);
      errors.add(
        'Target placement (${(distanceM / 1000).toStringAsFixed(2)} km) exceeds maximum one-way flight range '
        '(${(maxOneWayRangeM / 1000).toStringAsFixed(2)} km). Drone will exhaust 100% battery and crash $deficitKm km before reaching the station.',
      );
      recommendations.add('Move placement closer or assign a longer-range drone.');
    }
    // 2. Round-trip without reserve check (can drone ever return?)
    else if (roundTripBatteryPct > 100.0) {
      final requiredPct = roundTripBatteryPct.toStringAsFixed(0);
      errors.add(
        'Round-trip travel requires $requiredPct% battery capacity (exceeds 100%). '
        'Drone can reach the station but CANNOT return to base without draining whole battery and crashing in the field.',
      );
      recommendations.add(
        'Maximum safe round-trip radius with current battery is ${(maxRoundTripRangeM / 1000).toStringAsFixed(2)} km.',
      );
    }
    // 3. Safety reserve check (does it meet safety factor?)
    else if (totalFlightNeededPct > 98.0) {
      warnings.add(
        'Round-trip with ${reserveFactor}x safety reserve requires ${totalFlightNeededPct.toStringAsFixed(0)}% battery. '
        'Leaves almost no time (${_formatDuration(usableStationTimeS)}) on station.',
      );
      recommendations.add('Plan an intermediate relay drone to split the distance.');
    } else if (usableStationTimeS < minRecommendedStationTimeS) {
      warnings.add(
        'Usable coverage time on station is only ${_formatDuration(usableStationTimeS)} before auto-return triggers.',
      );
    }

    // 4. Area boundary check
    if (!isInsideArea) {
      warnings.add('Placement is outside the designated mission operation area polygon.');
      recommendations.add('Verify if mission boundary needs to be expanded or placement repositioned.');
    }

    // 5. Spec confidence check
    if (!hasSpecs) {
      warnings.add(
        'Drone "${drone.label}" has no cached battery specs. Feasibility is estimated using default ${fallbackEnduranceMin.toStringAsFixed(0)} min endurance.',
      );
      recommendations.add('Fetch specs from product site or enter battery capacity in Mission tab.');
    }

    final FeasibilityLevel level;
    if (errors.isNotEmpty) {
      level = FeasibilityLevel.impossible;
    } else if (warnings.isNotEmpty) {
      level = FeasibilityLevel.warning;
    } else {
      level = FeasibilityLevel.feasible;
    }

    return ValidationResult(
      level: level,
      metrics: metrics,
      errors: errors,
      warnings: warnings,
      recommendations: recommendations,
    );
  }

  /// Check a placement coordinate against mission bounds and distance to base.
  static PlacementCheckResult checkPlacementLocation({
    required double lat,
    required double lon,
    required MissionState mission,
    double? homeLat,
    double? homeLon,
  }) {
    final polygon = mission.area.map((p) => [p.lat, p.lon]).toList();
    final isInsideArea = polygon.length < 3 || pointInPolygon(lat, lon, polygon);

    double? distFromHomeM;
    if (homeLat != null && homeLon != null) {
      distFromHomeM = haversineM(homeLat, homeLon, lat, lon);
    } else if (mission.gccPosition != null) {
      distFromHomeM = haversineM(mission.gccPosition!.lat, mission.gccPosition!.lon, lat, lon);
    }

    final warnings = <String>[];
    if (!isInsideArea) {
      warnings.add('Placement is outside the designated operation area.');
    }
    if (distFromHomeM != null && distFromHomeM > 5000) {
      warnings.add(
        'Distance to base is ${(distFromHomeM / 1000).toStringAsFixed(1)} km. '
        'Verify drone battery capacity before deploying.',
      );
    }

    return PlacementCheckResult(
      isInsideArea: isInsideArea,
      distanceFromBaseM: distFromHomeM,
      warnings: warnings,
    );
  }

  static String _formatDuration(double seconds) {
    if (seconds <= 0) return '0 s';
    final s = seconds.round();
    final m = s ~/ 60;
    final remS = s % 60;
    if (m == 0) return '${remS}s';
    return '$m min ${remS}s';
  }
}

class PlacementCheckResult {
  final bool isInsideArea;
  final double? distanceFromBaseM;
  final List<String> warnings;

  const PlacementCheckResult({
    required this.isInsideArea,
    this.distanceFromBaseM,
    required this.warnings,
  });
}
