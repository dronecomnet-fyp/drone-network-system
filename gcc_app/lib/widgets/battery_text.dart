/// One place that turns a battery reading into words, so the Nodes card,
/// the Live Ops tiles, and the fleet table never describe the same pack
/// differently.
///
/// The point of interest is DIRECTION. Both aux battery channels are
/// bidirectional, so a pack on charge reports a negative current. Showing
/// a bare "-500 mA" would read as a fault to an operator; it is actually
/// good news, so the sign becomes a word and the number stays positive.
library;

import 'package:flutter/material.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

/// "7.80 V  590 mA draw" / "4.05 V  500 mA charging" / "4.05 V  idle".
/// Voltage with no current reading degrades to just the voltage, and a
/// channel the chip could not read at all is "n/a".
String batteryLine(double? volts, double? ma) {
  if (volts == null && ma == null) return 'n/a';
  final v = volts == null ? '' : '${volts.toStringAsFixed(2)} V';
  final flow = shared.batteryFlowFor(ma);
  switch (flow) {
    case shared.BatteryFlow.unknown:
      return v.isEmpty ? 'n/a' : v;
    case shared.BatteryFlow.idle:
      return v.isEmpty ? 'idle' : '$v  idle';
    case shared.BatteryFlow.charging:
    case shared.BatteryFlow.discharging:
      final word =
          flow == shared.BatteryFlow.charging ? 'charging' : 'draw';
      final n = '${ma!.abs().toStringAsFixed(0)} mA $word';
      return v.isEmpty ? n : '$v  $n';
  }
}

/// A small direction marker for the reading, or null when there is nothing
/// worth marking (no reading, or a resting line).
IconData? batteryFlowIcon(double? ma) {
  switch (shared.batteryFlowFor(ma)) {
    case shared.BatteryFlow.charging:
      return Icons.battery_charging_full;
    case shared.BatteryFlow.discharging:
      return Icons.arrow_downward;
    case shared.BatteryFlow.idle:
    case shared.BatteryFlow.unknown:
      return null;
  }
}

Color? batteryFlowColor(double? ma) {
  switch (shared.batteryFlowFor(ma)) {
    case shared.BatteryFlow.charging:
      return Colors.lightGreenAccent;
    case shared.BatteryFlow.discharging:
      return Colors.white70;
    case shared.BatteryFlow.idle:
    case shared.BatteryFlow.unknown:
      return null;
  }
}
