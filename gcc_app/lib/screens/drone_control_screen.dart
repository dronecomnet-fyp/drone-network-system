/// Drone Control (file 04 screen 6): SYSTEM DRONE ONLY, and staged.
///
/// This build is the Stage 0 GATE screen, deliberately: no telemetry, no
/// commands. Stage 0 (identify what is actually flashed on the Revo Mini
/// and its ESP32 bridge, props off, findings into docs/DRONE_LINK.md) is
/// mandatory before any control code exists (master plan D5). Stage 1
/// (MAVLink telemetry over the DRONE_S gateway, file 08) replaces this
/// screen in milestone M3; the safety gates from file 04 apply there.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/data_store.dart';

class DroneControlScreen extends StatelessWidget {
  const DroneControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = context.watch<DataStore>();
    final nodeId = data.health?.nodeId ?? '';
    final onSystemDrone = nodeId == 'DRONE_S';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flight, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Drone control: locked pending Stage 0',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Control of the system drone is gated on hardware '
                  'identification that has not run yet (file 04 Stage 0):\n\n'
                  '1. Connect the Revo Mini over USB, PROPS OFF.\n'
                  '2. Try Mission Planner, then Betaflight Configurator, '
                  'then LibrePilot GCS; record which one talks.\n'
                  '3. Identify the ESP32 bridge firmware.\n'
                  '4. Write all findings into docs/DRONE_LINK.md.\n\n'
                  'Stage 1 (telemetry through the DRONE_S MAVLink gateway) '
                  'lands in this tab only after DRONE_LINK.md is filled in. '
                  'Volunteer drones are never controllable from here: the '
                  'project builds communication modules only for them.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      onSystemDrone ? Icons.check_circle : Icons.info_outline,
                      size: 16,
                      color: onSystemDrone
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        onSystemDrone
                            ? 'Connected to RESCUE_S: DIRECT path available '
                                'once Stage 1 lands.'
                            : nodeId.isEmpty
                                ? 'Not connected to any node.'
                                : 'Connected to $nodeId: control would use '
                                    'the MESH RELAY path (${app.mavlinkTarget}).',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
