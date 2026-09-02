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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0F0A),
        border: Border(
            bottom: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
            ),
            child: const Icon(Icons.flight_takeoff, color: Colors.cyanAccent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SYSTEM DRONE',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.5,
                    )),
                const SizedBox(height: 4),
                Text('MAVLink  ·  Target: $target', 
                    style: const TextStyle(fontSize: 11, color: Colors.white38, letterSpacing: 0.3)),
              ],
            ),
          ),
          if (drone.connected)
            OutlinedButton.icon(
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Disconnect', style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
              onPressed: () => drone.disconnect(),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.link, size: 16),
              label: const Text('Connect', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.cyanAccent.withOpacity(0.15),
                foregroundColor: Colors.cyanAccent,
                side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
              ),
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
        constraints: const BoxConstraints(maxWidth: 500),
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flight_takeoff, size: 48, color: Colors.orangeAccent),
              ),
              const SizedBox(height: 24),
              const Text('NO MAVLINK CONNECTION',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 1.2,
                  )),
              const SizedBox(height: 12),
              const Text(
                'Connect to the system drone\'s Pi MAVLink gateway. Either '
                'join RESCUE_S for the direct path (10.42.0.1), or join a '
                'volunteer AP (RESCUE_A/B) for the live relay across the mesh '
                '(10.99.0.3). Set the target in Settings, then tap Connect.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.white54, height: 1.5),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
                ),
                child: Text('Target: $target',
                    style: const TextStyle(fontSize: 12, color: Colors.cyanAccent, fontWeight: FontWeight.w600)),
              ),
              if (drone.connectError != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(drone.connectError!,
                            style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'PROPS OFF FOR ALL GROUND TESTING',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.orangeAccent, letterSpacing: 1),
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
    
    final color = fresh ? Colors.greenAccent : Colors.redAccent;
    
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(fresh ? Icons.favorite : Icons.heart_broken,
                color: color, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fresh ? 'LINK ACTIVE' : 'LINK STALE',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    fresh
                        ? 'MAVLink heartbeat live. Commands enabled.'
                        : age == null
                            ? 'Waiting for the first heartbeat from the FC...'
                            : 'Heartbeat stale (${age.inSeconds}s). Commands disabled until the link recovers.',
                    style: const TextStyle(fontSize: 13, color: Colors.white70),
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

class _TelemetryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = context.watch<DroneController>().telemetry;
    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white38,
                        letterSpacing: 0.8)),
                const SizedBox(height: 4),
                Text(value,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color ?? Colors.white)),
              ],
            ),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.speed, size: 16, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              const Text('TELEMETRY',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: t.armed
                      ? Colors.redAccent.withOpacity(0.15)
                      : Colors.greenAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: t.armed
                          ? Colors.redAccent.withOpacity(0.4)
                          : Colors.greenAccent.withOpacity(0.4)),
                ),
                child: Text(
                  t.armed ? 'ARMED' : 'DISARMED',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: t.armed ? Colors.redAccent : Colors.greenAccent,
                      letterSpacing: 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              stat('Mode', t.modeName),
              const SizedBox(width: 8),
              stat('Battery',
                  t.batteryVolts == null
                      ? 'n/a'
                      : '${t.batteryVolts!.toStringAsFixed(2)} V'
                          '${t.batteryRemaining != null && t.batteryRemaining! >= 0 ? "  ${t.batteryRemaining}%" : ""}'),
              const SizedBox(width: 8),
              stat('GPS',
                  t.hasGpsFix
                      ? '3D fix, ${t.satellites} sats'
                      : 'no fix (${t.satellites} sats)',
                  color: t.hasGpsFix ? Colors.greenAccent : Colors.orangeAccent),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              stat('Attitude',
                  'R ${t.rollDeg.toStringAsFixed(0)}  P ${t.pitchDeg.toStringAsFixed(0)}  Y ${t.yawDeg.toStringAsFixed(0)}'),
              const SizedBox(width: 8),
              if (t.lat != null)
                stat('Position',
                    '${t.lat!.toStringAsFixed(5)}, ${t.lon!.toStringAsFixed(5)}'),
              if (t.lat == null)
                Expanded(child: Container()), // Empty placeholder
            ],
          ),
        ],
      ),
    );
  }
}

class _CommandPalette extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    final fresh = drone.linkFresh;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gamepad_outlined, size: 16, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              const Text('COMMANDS (PROPS OFF)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1)),
              const Spacer(),
              // The kill switch: always available while connected.
              FilledButton.icon(
                icon: const Icon(Icons.dangerous, size: 16),
                label: const Text('FORCE DISARM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.2),
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                ),
                onPressed: () => drone.forceDisarm(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fresh
                ? 'Link is live. Keep props OFF and the drone secured.'
                : 'Buttons below are disabled until the heartbeat is live.',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.lock_open, size: 16),
                label: const Text('ARM'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.15),
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(color: Colors.redAccent.withOpacity(0.3)),
                ),
                onPressed: fresh
                    ? () => _confirm(context, 'Arm the flight controller?',
                        'Props MUST be off. The motors will be able to '
                        'spin. Continue?', drone.arm)
                    : null,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.lock, size: 16),
                label: const Text('DISARM'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white54,
                  side: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
                onPressed: fresh ? () => drone.disarm() : null,
              ),
              const SizedBox(width: 12, height: 24), // Spacer
              for (var motor = 1; motor <= 4; motor++)
                FilledButton.icon(
                  icon: const Icon(Icons.settings_input_component, size: 16),
                  label: Text('MOTOR $motor'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.orangeAccent.withOpacity(0.15),
                    foregroundColor: Colors.orangeAccent,
                    side: BorderSide(color: Colors.orangeAccent.withOpacity(0.3)),
                  ),
                  onPressed: fresh
                      ? () => _confirm(
                          context,
                          'Spin motor $motor?',
                          'PROPS OFF. Motor $motor will spin briefly at low '
                          'throttle. Everyone clear of the drone?',
                          () => drone.motorTest(motor))
                      : null,
                ),
              const SizedBox(width: 12, height: 24), // Spacer
              OutlinedButton(
                onPressed: fresh
                    ? () => drone.setMode(CopterMode.stabilize)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
                ),
                child: const Text('MODE: STABILIZE'),
              ),
              OutlinedButton(
                onPressed:
                    fresh ? () => drone.setMode(CopterMode.guided) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.cyanAccent,
                  side: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
                ),
                child: const Text('MODE: GUIDED'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _AckLine(),
          const Divider(height: 24, color: Colors.white12),
          _GuidedStretch(fresh: fresh),
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context, String title, String body,
      VoidCallback onYes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1E1612),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.05),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                  border: Border(
                    bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: Colors.orangeAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.orangeAccent,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Text(
                      body,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white54,
                              side: BorderSide(
                                  color: Colors.white.withOpacity(0.15)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orangeAccent.withOpacity(0.2),
                              foregroundColor: Colors.orangeAccent,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(color: Colors.orangeAccent),
                            ),
                            child: const Text('Confirm',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accepted ? Colors.greenAccent.withOpacity(0.05) : Colors.orangeAccent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accepted ? Colors.greenAccent.withOpacity(0.2) : Colors.orangeAccent.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(accepted ? Icons.check_circle : Icons.error,
              size: 14,
              color: accepted ? Colors.greenAccent : Colors.orangeAccent),
          const SizedBox(width: 8),
          Text(
            'LAST COMMAND (${ack.command}): ${accepted ? "ACCEPTED" : "RESULT ${ack.result}"}',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: accepted ? Colors.greenAccent : Colors.orangeAccent,
                letterSpacing: 0.8),
          ),
        ],
      ),
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
        const Text('GUIDED REPOSITION (STRETCH)',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white38, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        Text(
          canGuided
              ? 'Requires an outdoor GPS fix, GUIDED mode, and armed. Sending '
                  'the drone to a map marker is the next milestone; for now '
                  'the motor test above is the proof of the command pipeline.'
              : 'Unavailable: needs a live link AND a 3D GPS fix. Indoors on '
                  'the bench there is no fix, so guided flight cannot be '
                  'commanded (expected).',
          style: const TextStyle(fontSize: 12, color: Colors.white54, height: 1.4),
        ),
      ],
    );
  }
}

class _StatusLog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final log = context.watch<DroneController>().statusLog;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF15100E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, size: 16, color: Colors.white38),
              const SizedBox(width: 8),
              const Text('FLIGHT CONTROLLER LOGS',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Colors.white38,
                      letterSpacing: 1)),
            ],
          ),
          const SizedBox(height: 12),
          if (log.isEmpty)
            const Text('No messages yet. The FC posts arming checks and '
                'status here (e.g. why it refused to arm).',
                style: TextStyle(fontSize: 12, color: Colors.white38))
          else
            ...log.take(12).map((s) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '[${s.severity}] ${s.text}',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: s.severity <= 3
                          ? Colors.redAccent
                          : (s.severity <= 5 ? Colors.orangeAccent : Colors.white54),
                    ),
                  ),
                )),
        ],
      ),
    );
  }
}
