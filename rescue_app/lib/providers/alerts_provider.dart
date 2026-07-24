/// AlertsProvider (task C): surfaces DEGRADED drones to rescue personnel.
///
/// When a drone's Raspberry Pi loses power, its aux module falls back to a
/// LoRa beacon, and a neighbouring node reports that drone as DEGRADED in
/// its /health. That is operationally important to a rescuer in the field
/// (a drone is down, coverage may have a hole), so this provider polls
/// /health and exposes the degraded list for a banner. /health is public,
/// so this works whether or not the rescuer is logged in.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../services/api_service.dart';

class AlertsProvider with ChangeNotifier {
  AlertsProvider() {
    _schedule(immediate: true);
  }

  static const Duration _interval = Duration(seconds: 15);

  Timer? _timer;
  List<shared.DegradedNode> _degraded = [];

  List<shared.DegradedNode> get degradedNodes => _degraded;

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    _timer = Timer(immediate ? Duration.zero : _interval, _poll);
  }

  Future<void> _poll() async {
    try {
      final h = await APIService.getHealth();
      _degraded = h.degradedNodes;
      notifyListeners();
    } catch (_) {
      // Node briefly unreachable: keep the last known list rather than
      // clearing an alert the rescuer may still need to act on.
    }
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
