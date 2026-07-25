/// Battery direction rules (pure Dart, no backend needed).
///
/// Both aux INA3221 battery channels are bidirectional: a pack on charge
/// reports a NEGATIVE current. These tests pin the convention the whole
/// fleet reads by (firmware/aux1/src/main.cpp publishes the sign; the apps
/// classify it), including the deadband that stops a resting line flapping
/// between charging and discharging on sensor noise.
///
/// Run from shared_dart/: dart test test/battery_flow_test.dart
library;

import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:test/test.dart';

void main() {
  group('batteryFlowFor', () {
    test('positive current is discharging', () {
      expect(batteryFlowFor(590.0), BatteryFlow.discharging);
      expect(batteryFlowFor(kBatteryIdleMa + 0.1), BatteryFlow.discharging);
    });

    test('negative current is charging', () {
      expect(batteryFlowFor(-500.0), BatteryFlow.charging);
      expect(batteryFlowFor(-(kBatteryIdleMa + 0.1)), BatteryFlow.charging);
    });

    test('small magnitudes either side of zero are idle, not a direction',
        () {
      expect(batteryFlowFor(0.0), BatteryFlow.idle);
      expect(batteryFlowFor(0.4), BatteryFlow.idle);
      expect(batteryFlowFor(-0.4), BatteryFlow.idle);
      expect(batteryFlowFor(kBatteryIdleMa - 0.1), BatteryFlow.idle);
      expect(batteryFlowFor(-(kBatteryIdleMa - 0.1)), BatteryFlow.idle);
    });

    test('no reading is unknown, which is not the same as zero current', () {
      expect(batteryFlowFor(null), BatteryFlow.unknown);
      expect(batteryFlowFor(0.0), isNot(BatteryFlow.unknown));
    });
  });

  group('BatteryState', () {
    test('classifies each battery independently', () {
      // The realistic mixed case: A running the Pi while B is on charge.
      const b = BatteryState(aV: 7.8, aMa: 590.0, bV: 4.05, bMa: -500.0);
      expect(b.flowA, BatteryFlow.discharging);
      expect(b.flowB, BatteryFlow.charging);
    });

    test('magnitude helpers drop the sign for display', () {
      const b = BatteryState(aMa: -500.0, bMa: 120.0);
      expect(b.aMaAbs, 500.0);
      expect(b.bMaAbs, 120.0);
      expect(const BatteryState().aMaAbs, isNull);
    });

    test('parses a negative (charging) current from node JSON', () {
      final b = BatteryState.fromJson(const {
        'a_v': 7.8,
        'a_ma': 590.0,
        'b_v': 4.05,
        'b_ma': -500.0,
      });
      expect(b.bMa, -500.0);
      expect(b.flowB, BatteryFlow.charging);
    });

    test('a channel the chip could not read stays null, not zero', () {
      final b = BatteryState.fromJson(const {'a_v': 7.8, 'a_ma': 590.0});
      expect(b.bV, isNull);
      expect(b.bMa, isNull);
      expect(b.flowB, BatteryFlow.unknown);
    });
  });
}
