import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/services/mission_validator.dart';
import 'package:gcc_app/state/mission_state.dart';

void main() {
  group('MissionValidator Tests', () {
    late MissionState mission;

    setUp(() {
      mission = MissionState();
      mission.area.addAll([
        const GeoPoint(6.927079, 79.861244),
        const GeoPoint(6.927079, 79.871244),
        const GeoPoint(6.917079, 79.871244),
        const GeoPoint(6.917079, 79.861244),
      ]);
    });

    test('Feasible deployment with verified specs', () {
      final drone = DroneResource(label: 'Alpha-1', unitId: 'U-001');
      mission.cacheProduct(
        'U-001',
        const ProductInfo(
          modelNo: 'RM-D1',
          name: 'Rescue Quad',
          specs: {'battery_wh': 50.0}, // 50 Wh @ 150 W = 20 min (1200 s)
          fetchedAt: '2026-09-02T00:00:00Z',
        ),
      );

      // 500 meters away (inside area)
      final placement = DronePlacement(
        name: 'Relay-North',
        lat: 6.922079,
        lon: 79.865244,
        radiusM: 300,
      );

      final result = MissionValidator.validateDroneDeployment(
        drone: drone,
        placement: placement,
        mission: mission,
        homeLat: 6.920079,
        homeLon: 79.865244,
        cruiseSpeedMs: 8.0,
        avgPowerW: 150.0,
      );

      expect(result.isFeasible, isTrue);
      expect(result.errors, isEmpty);
      expect(result.metrics.hasSpecs, isTrue);
      expect(result.metrics.isInsideArea, isTrue);
      expect(result.metrics.usableStationTimeS, greaterThan(600)); // over 10 min station time
    });

    test('Impossible deployment: placement too far (round-trip requires >100% battery)', () {
      final drone = DroneResource(label: 'Small-Drone', unitId: 'U-002');
      mission.cacheProduct(
        'U-002',
        const ProductInfo(
          modelNo: 'RM-MINI',
          name: 'Mini Drone',
          specs: {'battery_wh': 10.0}, // 10 Wh @ 150 W = 240 s (4 min)
          fetchedAt: '2026-09-02T00:00:00Z',
        ),
      );

      // Target ~3 km away -> at 8 m/s, round trip is 6 km = 750 s flight time (needs 312% battery)
      final placement = DronePlacement(
        name: 'Distant-Post',
        lat: 6.950000,
        lon: 79.865244,
        radiusM: 300,
      );

      final result = MissionValidator.validateDroneDeployment(
        drone: drone,
        placement: placement,
        mission: mission,
        homeLat: 6.920079,
        homeLon: 79.865244,
        cruiseSpeedMs: 8.0,
        avgPowerW: 150.0,
      );

      expect(result.isImpossible, isTrue);
      expect(result.errors.isNotEmpty, isTrue);
      expect(result.errors.first, contains('exceeds'));
    });

    test('Warning deployment: outside operation area', () {
      final drone = DroneResource(label: 'Alpha-1', unitId: 'U-001');
      mission.cacheProduct(
        'U-001',
        const ProductInfo(
          modelNo: 'RM-D1',
          name: 'Rescue Quad',
          specs: {'battery_wh': 50.0},
          fetchedAt: '2026-09-02T00:00:00Z',
        ),
      );

      // Outside polygon (lat 6.99)
      final placement = DronePlacement(
        name: 'Outside-Post',
        lat: 6.990000,
        lon: 79.865244,
        radiusM: 300,
      );

      final result = MissionValidator.validateDroneDeployment(
        drone: drone,
        placement: placement,
        mission: mission,
        homeLat: 6.980000,
        homeLon: 79.865244,
        cruiseSpeedMs: 8.0,
        avgPowerW: 150.0,
      );

      expect(result.isWarning, isTrue);
      expect(result.metrics.isInsideArea, isFalse);
      expect(result.warnings.any((w) => w.contains('outside')), isTrue);
    });

    test('Warning deployment: drone without specs uses fallback', () {
      final drone = DroneResource(label: 'Volunteer-1'); // No specs

      final placement = DronePlacement(
        name: 'Station-1',
        lat: 6.922079,
        lon: 79.865244,
        radiusM: 300,
      );

      final result = MissionValidator.validateDroneDeployment(
        drone: drone,
        placement: placement,
        mission: mission,
        homeLat: 6.920079,
        homeLon: 79.865244,
      );

      expect(result.isWarning, isTrue);
      expect(result.metrics.hasSpecs, isFalse);
      expect(result.warnings.any((w) => w.contains('no cached battery specs')), isTrue);
    });
  });
}
