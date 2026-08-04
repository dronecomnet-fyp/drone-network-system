/// A prominent alert for drones that have dropped to LoRa fallback (task C):
/// a node whose Raspberry Pi lost power is heard only through its aux
/// module's LoRa beacon, and a neighbouring node reports it as a DEGRADED
/// node in /health. That is an operational emergency (a drone is down), so
/// it is elevated from the Nodes tab card to a red banner on the main
/// screens. Renders nothing when no node is degraded.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart' show ShellNav;
import '../state/data_store.dart';

class DegradedAlert extends StatelessWidget {
  const DegradedAlert({super.key});

  @override
  Widget build(BuildContext context) {
    final degraded = context.watch<DataStore>().health?.degradedNodes ??
        const [];
    if (degraded.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.red.shade900,
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                    '${degraded.length} DRONE${degraded.length > 1 ? "S" : ""} '
                    'ON LORA FALLBACK (Pi down)',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  ...degraded.map((d) => Text(
                        '${d.nodeId}: aux LoRa beacon'
                        '${d.lat != null ? " at ${d.lat!.toStringAsFixed(5)}, ${d.lon!.toStringAsFixed(5)}" : ""}'
                        ' (last ${d.ts})',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      )),
                  // The banner says a drone is down; the tab says what it
                  // has been telling us since. Without this the operator
                  // reads the alert and has nowhere to go with it.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () =>
                          context.read<ShellNav>().go(ShellNav.degradedTab),
                      child: const Text('Open the LoRa log',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
