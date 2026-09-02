/// Nodes (file 04 screen 3): health of the CONNECTED node from /health,
/// its alive-peer table, and DEGRADED nodes learned from LoRa fallback
/// beacons. Every block carries a last-updated age; remote nodes are only
/// as fresh as DTN sync plus beacons (file 04 connectivity model).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../services/portal_config.dart';
import '../state/app_state.dart';
import '../state/data_store.dart';
import '../state/mission_state.dart';
import '../widgets/battery_text.dart';
import '../widgets/drone_glyph.dart';

class NodesScreen extends StatelessWidget {
  const NodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final h = data.health;

    final nodeCount = h == null ? 0 : (h.peers.length + 1);
    final age = data.healthUpdated == null
        ? 'never updated'
        : 'updated ${formatAge(DateTime.now().difference(data.healthUpdated!))}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Command-center header (matches Live Feed) ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0F0A),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.08), width: 1),
            ),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: h != null ? Colors.cyanAccent : Colors.white24,
                          shape: BoxShape.circle,
                          boxShadow: h != null
                              ? [
                                  BoxShadow(
                                    color: Colors.cyanAccent.withOpacity(0.5),
                                    blurRadius: 6,
                                  )
                                ]
                              : [],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'NODES',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$nodeCount node${nodeCount == 1 ? '' : 's'} known  ·  $age',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.white38, letterSpacing: 0.3),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Scrollable content ──
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (data.lastError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(data.lastError!,
                            style:
                                const TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ),
              if (h == null)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(14),
                    border:
                        Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.white38, size: 22),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No node in range yet. Join a RESCUE_x WiFi; the health poll runs every 5 seconds.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // ── Connected node + Fleet peers side by side ──
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ConnectedNodeCard(
                            healthUpdated: data.healthUpdated),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: _PeersCard()),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                const _PortalConfigCard(),
                const SizedBox(height: 10),
                _DegradedCard(),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectedNodeCard extends StatelessWidget {
  final DateTime? healthUpdated;

  const _ConnectedNodeCard({this.healthUpdated});

  String _uptime(int s) {
    final h = s ~/ 3600, m = (s % 3600) ~/ 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<DataStore>().health!;
    final gps = h.gps;
    final bat = h.battery;
    return Container(
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.25)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const DroneGlyph(color: Colors.cyanAccent, size: 46),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          h.nodeId,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.greenAccent.withOpacity(0.5)),
                          ),
                          child: const Text(
                            'CONNECTED',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.greenAccent,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        if (h.aux == 'absent') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.orangeAccent.withOpacity(0.4)),
                            ),
                            child: const Text('aux absent',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orangeAccent)),
                          ),
                        ],
                      ],
                    ),
                    if (healthUpdated != null)
                      Text(
                        'health ${formatAge(DateTime.now().difference(healthUpdated!))}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white38),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ── Stats grid: 2-column bordered tiles ──
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'GPS',
                      gps.hasFix
                          ? '${gps.lat!.toStringAsFixed(5)}, ${gps.lon!.toStringAsFixed(5)}'
                          : 'no fix',
                      icon: gps.hasFix ? Icons.gps_fixed : Icons.gps_not_fixed,
                      iconColor: gps.hasFix ? Colors.greenAccent : Colors.orangeAccent,
                      sub: gps.hasFix ? '${gps.sats} satellites' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stat('Uptime', _uptime(h.uptimeS),
                        icon: Icons.timer_outlined,
                        iconColor: Colors.cyanAccent),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'Battery A',
                      batteryLine(bat.aV, bat.aMa),
                      icon: batteryFlowIcon(bat.aMa) ?? Icons.battery_unknown,
                      iconColor: batteryFlowColor(bat.aMa) ?? Colors.white54,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stat(
                      'Battery B',
                      batteryLine(bat.bV, bat.bMa),
                      icon: batteryFlowIcon(bat.bMa) ?? Icons.battery_unknown,
                      iconColor: batteryFlowColor(bat.bMa) ?? Colors.white54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _stat(
                      'Clock',
                      h.clockSource,
                      icon: Icons.access_time,
                      iconColor: h.clockSource == 'gps'
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      warn: h.clockSource != 'gps',
                      warnText: 'Timestamps approximate until GPS fix',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _stat(
                      'Messages',
                      h.messageCounts.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join('  '),
                      icon: Icons.message_outlined,
                      iconColor: Colors.purpleAccent,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(
    String label,
    String value, {
    bool warn = false,
    String warnText = '',
    IconData? icon,
    Color? iconColor,
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 12, color: iconColor ?? Colors.white38),
                const SizedBox(width: 5),
              ],
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: iconColor?.withOpacity(0.7) ?? Colors.white38,
                  letterSpacing: 0.8,
                ),
              ),
              if (warn) ...[
                const SizedBox(width: 4),
                Tooltip(
                  message: warnText,
                  child: const Icon(Icons.info_outline,
                      size: 12, color: Colors.orangeAccent),
                ),
              ],
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub,
                style:
                    const TextStyle(fontSize: 10, color: Colors.white38)),
          ],
        ],
      ),
    );
  }
}

class _PeersCard extends StatelessWidget {
  /// How old the cached position/battery beside it actually is. "never"
  /// means we have not managed to reach that peer's /health yet, which is
  /// what an un-updated node looks like.
  String _healthAge(shared.PeerInfo p) {
    if (!p.hasHealth) return 'never';
    final t = DateTime.tryParse(p.healthTs!);
    if (t == null) return '-';
    return formatAge(DateTime.now().difference(t));
  }

  /// Seconds since this peer last beaconed, or null if unparseable. Used
  /// to decide whether the card reads as live or stale.
  int? _beaconAgeS(shared.PeerInfo p) {
    final t = DateTime.tryParse(p.lastSeen);
    if (t == null) return null;
    return DateTime.now().toUtc().difference(t.toUtc()).inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<DataStore>().health!;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_outlined, size: 16, color: Colors.cyanAccent),
              const SizedBox(width: 8),
              const Text(
                'Fleet Peers',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'as seen by ${h.nodeId}',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (h.peers.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.orange.shade900.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.orangeAccent, size: 16),
                      SizedBox(width: 8),
                      Text('No other drone in range right now.',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'For a delay-tolerant mesh this is normal. If this node should be hearing someone, check for a dead USB WiFi adapter.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.white.withOpacity(0.5)),
                  ),
                ],
              ),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children:
                  h.peers.map((p) => _peerCard(context, p)).toList(),
            ),
        ],
      ),
    );
  }

  Widget _peerCard(BuildContext context, shared.PeerInfo p) {
    final ageS = _beaconAgeS(p);
    // 90 s is three beacon intervals at the default 30 s. One missed
    // beacon is nothing; three means something.
    final stale = ageS == null || ageS > 90;
    final colour = stale ? Colors.orangeAccent : Colors.cyanAccent;

    return Container(
      width: 330,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: colour.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DroneGlyph(color: colour, size: 54, dimmed: stale),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(p.nodeId,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Chip(
                      label: Text(stale ? 'no recent beacon' : 'in range',
                          style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: stale
                          ? Colors.orange.shade900
                          : Colors.green.shade900,
                    ),
                  ],
                ),
                Text(p.ip,
                    style: const TextStyle(fontSize: 11, color: Colors.white54)),
                const SizedBox(height: 6),
                Text(p.hasFix
                    ? '${p.lat!.toStringAsFixed(5)}, ${p.lon!.toStringAsFixed(5)}'
                    : (p.hasHealth ? 'GPS: no fix' : 'position not fetched yet')),
                const SizedBox(height: 4),
                Row(children: [
                  if (batteryFlowIcon(p.batAMa) != null) ...[
                    Icon(batteryFlowIcon(p.batAMa),
                        size: 13, color: batteryFlowColor(p.batAMa)),
                    const SizedBox(width: 3),
                  ],
                  Text('A ${batteryLine(p.batAV, p.batAMa)}',
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 10),
                  if (batteryFlowIcon(p.batBMa) != null) ...[
                    Icon(batteryFlowIcon(p.batBMa),
                        size: 13, color: batteryFlowColor(p.batBMa)),
                    const SizedBox(width: 3),
                  ],
                  Text('B ${batteryLine(p.batBV, p.batBMa)}',
                      style: const TextStyle(fontSize: 12)),
                ]),
                const SizedBox(height: 6),
                // Two ages, not one. A peer can be beaconing right now
                // while the position and battery beside it are minutes
                // old, and collapsing them into a single "last seen" hid
                // exactly that.
                Text(
                  'beacon ${ageS == null ? "unknown" : formatAge(Duration(seconds: ageS))}'
                  ', details ${_healthAge(p)}',
                  style: const TextStyle(fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DegradedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final h = context.watch<DataStore>().health!;
    if (h.degradedNodes.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.report, color: Colors.redAccent, size: 18),
              SizedBox(width: 8),
              Text(
                'DEGRADED NODES',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.redAccent,
                  letterSpacing: 0.8,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'LoRa fallback beacons',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...h.degradedNodes.map((d) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: Colors.redAccent.withOpacity(0.25)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DroneGlyph(
                        color: Colors.redAccent, size: 40, dimmed: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.nodeId,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Colors.redAccent),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pi down, aux module beaconing  ·  last ${d.ts}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white54),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (d.lat != null)
                                'GPS ${d.lat!.toStringAsFixed(5)}, ${d.lon!.toStringAsFixed(5)}',
                              if (d.batAV != null)
                                'bat A ${d.batAV!.toStringAsFixed(2)} V',
                              if (d.batBV != null)
                                'bat B ${d.batBV!.toStringAsFixed(2)} V',
                            ].join('  ·  '),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

/// What the connected node is showing victims, and a way to change it.
///
/// This is deliberately on the Nodes tab rather than buried in Mission:
/// the question it answers is "is THIS node actually updated", and the
/// honest answer differs per node during a rollout. A fleet where one node
/// still serves stock options while the others are mission-specific is an
/// easy state to end up in and a hard one to notice from anywhere else.
class _PortalConfigCard extends StatefulWidget {
  const _PortalConfigCard();

  @override
  State<_PortalConfigCard> createState() => _PortalConfigCardState();
}

class _PortalConfigCardState extends State<_PortalConfigCard> {
  bool _busy = false;

  Future<void> _push(BuildContext context) async {
    final app = context.read<AppState>();
    final mission = context.read<MissionState>();
    final data = context.read<DataStore>();
    final messenger = ScaffoldMessenger.of(context);

    if (mission.missionName.trim().isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Name the mission first, on the Mission tab.')));
      return;
    }

    final situations = effectiveSituations(
        edited: mission.portalOptions, disasterType: mission.disasterType);
    final cfg = data.health?.missionConfig ?? const shared.MissionConfigSummary();
    // A node already running a mission, and not this one.
    final switchesMission = !cfg.isStock &&
        cfg.missionId.isNotEmpty &&
        cfg.missionId != mission.ensureMissionId();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(switchesMission
            ? 'Switch this drone to a different mission?'
            : 'Push these options to this node?'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Every victim who connects to this drone will see these '
                  'as tappable buttons, for a ${mission.disasterType} '
                  'mission.'),
              const SizedBox(height: 10),
              ...situations.map((s) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [
                      Icon(
                          s['urgent'] == true
                              ? Icons.priority_high
                              : Icons.circle_outlined,
                          size: 14,
                          color: s['urgent'] == true
                              ? Colors.redAccent
                              : Colors.white54),
                      const SizedBox(width: 6),
                      Expanded(child: Text('${s['label']}')),
                    ]),
                  )),
              const SizedBox(height: 10),
              Text(
                'This pushes to the CONNECTED node only. Join each drone in '
                'turn and push again; the version column shows who is done.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              // Pushing a different mission id retires every credential
              // issued under the old one on this node, immediately. That is
              // intended, but it must never be a quiet side effect of a
              // button labelled "push options".
              if (switchesMission) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This drone is running a DIFFERENT mission. Pushing '
                        'retires every credential issued for it, so rescuers '
                        'still using those will be signed out of this drone '
                        'and will need new ones.',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              style: switchesMission
                  ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                  : null,
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(switchesMission ? 'Switch mission' : 'Push')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final result = await app.client.pushMissionConfig(buildPortalConfig(
        missionId: mission.ensureMissionId(),
        missionName: mission.missionName,
        disasterType: mission.disasterType,
        situations: situations,
      ));
      messenger.showSnackBar(SnackBar(
          content: Text('${data.health?.nodeId ?? "Node"} is now serving '
              'these options (${result['config_id']}).')));
    } catch (e) {
      // A push that did not land must never look like one that did.
      messenger.showSnackBar(SnackBar(
          content: Text('Push failed: $e'), duration: const Duration(seconds: 8)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final app = context.watch<AppState>();
    final cfg = data.health?.missionConfig;
    if (cfg == null) return const SizedBox.shrink();

    final mission = context.watch<MissionState>();
    final wanted = portalConfigId(situations: effectiveSituations(edited: mission.portalOptions, disasterType: mission.disasterType));
    final matches = cfg.matches(wanted);
    final chipLabel = cfg.isStock
        ? 'stock options'
        : (matches ? 'matches this mission' : 'different options');
    final chipColor = cfg.isStock
        ? Colors.orangeAccent
        : (matches ? Colors.greenAccent : Colors.blueAccent);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: chipColor.withOpacity(0.3),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.broadcast_on_personal_outlined,
                size: 16, color: chipColor),
            const SizedBox(width: 8),
            const Text(
              'Victim Portal Options',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: chipColor.withOpacity(0.5)),
              ),
              child: Text(
                chipLabel.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: chipColor,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            cfg.isStock
                ? 'This node serves the built-in need-based options. That works, it is just not tailored to this mission.'
                : matches
                    ? 'Serving ${cfg.situationCount} options for "${cfg.missionName}". Nothing to do.'
                    : 'Serving ${cfg.situationCount} options for "${cfg.missionName}", which are NOT the ones this mission would push.',
            style: const TextStyle(fontSize: 12, color: Colors.white54),
          ),
          const SizedBox(height: 12),
          if (!app.isHq)
            Text('HQ login required to change what victims are shown.',
                style: const TextStyle(fontSize: 12, color: Colors.white38))
          else
            FilledButton.icon(
              onPressed: _busy ? null : () => _push(context),
              icon: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.upload, size: 16),
              label: Text(_busy ? 'Pushing...' : 'Push mission options'),
            ),
        ],
      ),
    );
  }
}
