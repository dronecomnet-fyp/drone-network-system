/// A red banner shown above every tab when a drone is on LoRa fallback
/// (task C). Driven by AlertsProvider; renders nothing when nothing is
/// degraded.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../providers/alerts_provider.dart';

class RescueAlertBanner extends StatelessWidget {
  const RescueAlertBanner({super.key});

  String _lineFor(shared.DegradedNode d) {
    if (d.lat == null || d.lon == null) {
      return '${d.nodeId}: last position unknown';
    }
    final lat = d.lat!.toStringAsFixed(4);
    final lon = d.lon!.toStringAsFixed(4);
    return '${d.nodeId}: last position $lat, $lon';
  }

  @override
  Widget build(BuildContext context) {
    final degraded = context.watch<AlertsProvider>().degradedNodes;
    if (degraded.isEmpty) {
      return const SizedBox.shrink();
    }
    return Material(
      color: Colors.red.shade700,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${degraded.length} drone${degraded.length > 1 ? "s" : ""} '
                    'down (LoRa fallback)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  ...degraded.map((d) => Text(
                        _lineFor(d),
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
