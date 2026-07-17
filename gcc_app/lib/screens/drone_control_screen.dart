/// Drone Control (file 04 screen 6): SYSTEM DRONE ONLY, staged and
/// safety-gated. This phase targets PROPS-OFF ground testing over the
/// ESP32 DroneBridge link to the CC3D Revo Mini.
///
/// Safety rules enforced here (file 04 / file 08):
///   - Every command button is disabled unless the MAVLink heartbeat is
///     fresher than 2 s (DroneController.linkFresh). A dead link greys the
///     whole command palette automatically.
///   - The kill switch (force DISARM) is always visible and always enabled
///     whenever connected.
///   - Arming and motor test each require an explicit confirm dialog.
///   - The headline action is a MOTOR TEST (spins one motor at low throttle
///     on the bench), not an armed takeoff. Guided "go to marker" is a
///     clearly-labelled stretch that needs a GPS fix.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../mavlink/mav_service.dart';
import '../state/app_state.dart';
import '../state/drone_controller.dart';

class DroneControlScreen extends StatelessWidget {
  const DroneControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    final app = context.watch<AppState>();

    return Column(
      children: [
        _ConnectionBar(target: app.mavlinkTarget),
        const Divider(height: 1),
        Expanded(
          child: !drone.connected
              ? _DisconnectedHelp(target: app.mavlinkTarget)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _LinkStatusCard(),
                    const SizedBox(height: 12),
                    _TelemetryCard(),
                    const SizedBox(height: 12),
                    _CommandPalette(),
                    const SizedBox(height: 12),
                    _StatusLog(),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ConnectionBar extends StatelessWidget {
  final String target;
  const _ConnectionBar({required this.target});

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.flight, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('System drone (MAVLink)',
                    style: Theme.of(context).textTheme.titleMedium),
                Text(target, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          if (drone.connected)
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              onPressed: () => drone.disconnect(),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.link),
              label: const Text('Connect'),
              onPressed: () => drone.connect(target),
            ),
        ],
      ),
    );
  }
}

class _DisconnectedHelp extends StatelessWidget {
  final String target;
  const _DisconnectedHelp({required this.target});

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Not connected to the flight controller',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              const Text(
                'Connect to the system drone\'s Pi MAVLink gateway. Either '
                'join RESCUE_S for the direct path (10.42.0.1), or join a '
                'volunteer AP (RESCUE_A/B) for the live relay across the mesh '
                '(10.99.0.3). Set the target in Settings, then tap Connect. '
                'Props OFF for all ground testing.',
              ),
              const SizedBox(height: 12),
              Text('Target: $target',
                  style: Theme.of(context).textTheme.bodySmall),
              if (drone.connectError != null) ...[
                const SizedBox(height: 12),
                Text(drone.connectError!,
                    style: const TextStyle(color: Colors.redAccent)),
              ],
              const SizedBox(height: 16),
              const Text(
                'The relay path is live-only (never store-and-forward): '
                'commands travel over a live link or not at all. See '
                'docs/DRONE_LINK.md for the architecture.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkStatusCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    final fresh = drone.linkFresh;
    final age = drone.sinceHeartbeat;
    return Card(
      color: fresh
          ? Colors.green.shade900.withValues(alpha: 0.25)
          : Colors.red.shade900.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(fresh ? Icons.favorite : Icons.heart_broken,
                color: fresh ? Colors.greenAccent : Colors.redAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                fresh
                    ? 'MAVLink heartbeat live. Commands enabled.'
                    : age == null
                        ? 'Waiting for the first heartbeat from the FC...'
                        : 'Heartbeat stale (${age.inSeconds}s). Commands '
                            'disabled until the link recovers.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TelemetryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.watch<DroneController>().telemetry;
    Widget stat(String label, String value, {Color? color}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white54)),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          ],
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Telemetry',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Chip(
                  label: Text(t.armed ? 'ARMED' : 'DISARMED'),
                  backgroundColor:
                      t.armed ? Colors.red.shade800 : Colors.green.shade800,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 26,
              runSpacing: 12,
              children: [
                stat('Mode', t.modeName),
                stat('Battery',
                    t.batteryVolts == null
                        ? 'n/a'
                        : '${t.batteryVolts!.toStringAsFixed(2)} V'
                            '${t.batteryRemaining != null && t.batteryRemaining! >= 0 ? "  ${t.batteryRemaining}%" : ""}'),
                stat('GPS',
                    t.hasGpsFix
                        ? '3D fix, ${t.satellites} sats'
                        : 'no fix (${t.satellites} sats)',
                    color: t.hasGpsFix ? Colors.greenAccent : Colors.orangeAccent),
                if (t.lat != null)
                  stat('Position',
                      '${t.lat!.toStringAsFixed(5)}, ${t.lon!.toStringAsFixed(5)}'),
                stat('Attitude',
                    'R ${t.rollDeg.toStringAsFixed(0)}  P ${t.pitchDeg.toStringAsFixed(0)}  Y ${t.yawDeg.toStringAsFixed(0)}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandPalette extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    final fresh = drone.linkFresh;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Commands (props off)',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                // The kill switch: always available while connected.
                FilledButton.icon(
                  icon: const Icon(Icons.dangerous),
                  label: const Text('DISARM'),
                  style: FilledButton.styleFrom(
                      backgroundColor: Colors.red.shade700),
                  onPressed: () => drone.forceDisarm(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              fresh
                  ? 'Link is live. Keep props OFF and the drone secured.'
                  : 'Buttons below are disabled until the heartbeat is live.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonal(
                  onPressed: fresh
                      ? () => _confirm(context, 'Arm the flight controller?',
                          'Props MUST be off. The motors will be able to '
                          'spin. Continue?', drone.arm)
                      : null,
                  child: const Text('Arm'),
                ),
                OutlinedButton(
                  onPressed: fresh ? () => drone.disarm() : null,
                  child: const Text('Disarm'),
                ),
                for (var motor = 1; motor <= 4; motor++)
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.settings_input_component, size: 16),
                    label: Text('Motor $motor'),
                    onPressed: fresh
                        ? () => _confirm(
                            context,
                            'Spin motor $motor?',
                            'PROPS OFF. Motor $motor will spin briefly at low '
                            'throttle. Everyone clear of the drone?',
                            () => drone.motorTest(motor))
                        : null,
                  ),
                OutlinedButton(
                  onPressed: fresh
                      ? () => drone.setMode(CopterMode.stabilize)
                      : null,
                  child: const Text('Mode: STABILIZE'),
                ),
                OutlinedButton(
                  onPressed:
                      fresh ? () => drone.setMode(CopterMode.guided) : null,
                  child: const Text('Mode: GUIDED'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _AckLine(),
            const Divider(height: 24),
            _GuidedStretch(fresh: fresh),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, String title, String body,
      VoidCallback onYes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm')),
        ],
      ),
    );
    if (ok == true) onYes();
  }
}

class _AckLine extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    final ack = drone.lastAck;
    if (ack == null) return const SizedBox.shrink();
    // MAV_RESULT: 0 = ACCEPTED.
    final accepted = ack.result == 0;
    return Row(
      children: [
        Icon(accepted ? Icons.check_circle : Icons.error,
            size: 16,
            color: accepted ? Colors.greenAccent : Colors.orangeAccent),
        const SizedBox(width: 6),
        Text(
          'Last command (${ack.command}): '
          '${accepted ? "accepted" : "result ${ack.result}"}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _GuidedStretch extends StatelessWidget {
  final bool fresh;
  const _GuidedStretch({required this.fresh});

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    final canGuided = fresh && drone.telemetry.hasGpsFix;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Guided reposition (stretch)',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          canGuided
              ? 'Requires an outdoor GPS fix, GUIDED mode, and armed. Sending '
                  'the drone to a map marker is the next milestone; for now '
                  'the motor test above is the proof of the command pipeline.'
              : 'Unavailable: needs a live link AND a 3D GPS fix. Indoors on '
                  'the bench there is no fix, so guided flight cannot be '
                  'commanded (expected).',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatusLog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final log = context.watch<DroneController>().statusLog;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flight controller messages',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (log.isEmpty)
              const Text('No messages yet. The FC posts arming checks and '
                  'status here (e.g. why it refused to arm).',
                  style: TextStyle(fontSize: 12, color: Colors.grey))
            else
              ...log.take(12).map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '[${s.severity}] ${s.text}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: s.severity <= 3
                            ? Colors.redAccent
                            : (s.severity <= 5 ? Colors.orangeAccent : null),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
