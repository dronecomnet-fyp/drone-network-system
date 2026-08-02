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

class NodesScreen extends StatelessWidget {
  const NodesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final h = data.health;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Nodes', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 12),
            Text(
                data.healthUpdated == null
                    ? 'never updated'
                    : 'updated ${formatAge(DateTime.now().difference(data.healthUpdated!))}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        if (data.lastError != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(data.lastError!),
            ),
          ),
        if (h == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('No node in range yet. Join a RESCUE_x WiFi; the '
                  'health poll runs every 5 seconds.'),
            ),
          )
        else ...[
          _ConnectedNodeCard(healthUpdated: data.healthUpdated),
          const SizedBox(height: 8),
          const _PortalConfigCard(),
          const SizedBox(height: 8),
          _PeersCard(),
          const SizedBox(height: 8),
          _DegradedCard(),
        ],
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(h.nodeId, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(width: 8),
                Chip(
                  label: Text('connected'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: Colors.green.shade900,
                ),
                const SizedBox(width: 8),
                if (h.aux == 'absent')
                  const Chip(
                    label: Text('aux absent'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                _stat('GPS',
                    gps.hasFix
                        ? '${gps.lat!.toStringAsFixed(5)}, ${gps.lon!.toStringAsFixed(5)} (${gps.sats} sats)'
                        : 'no fix'),
                _stat('Battery A', batteryLine(bat.aV, bat.aMa),
                    icon: batteryFlowIcon(bat.aMa),
                    iconColor: batteryFlowColor(bat.aMa)),
                _stat('Battery B', batteryLine(bat.bV, bat.bMa),
                    icon: batteryFlowIcon(bat.bMa),
                    iconColor: batteryFlowColor(bat.bMa)),
                _stat('Uptime', _uptime(h.uptimeS)),
                _stat('Clock', h.clockSource,
                    warn: h.clockSource != 'gps',
                    warnText: 'timestamps approximate until GPS fix'),
                _stat(
                    'Messages',
                    h.messageCounts.entries
                        .map((e) => '${e.key}: ${e.value}')
                        .join('   ')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value,
      {bool warn = false,
      String warnText = '',
      IconData? icon,
      Color? iconColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 4),
            ],
            Text(value),
            if (warn) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: warnText,
                child: const Icon(Icons.info_outline,
                    size: 14, color: Colors.orangeAccent),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _PeersCard extends StatelessWidget {
  /// "HH:mm:ss" from an ISO stamp; the raw string is too wide for a cell.
  String _shortTime(String iso) {
    final t = DateTime.tryParse(iso);
    if (t == null) return iso;
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}:'
        '${l.second.toString().padLeft(2, '0')}';
  }

  /// How old the cached position/battery beside it actually is. "never"
  /// means we have not managed to reach that peer's /health yet, which is
  /// what an un-updated node looks like.
  String _healthAge(shared.PeerInfo p) {
    if (!p.hasHealth) return 'never';
    final t = DateTime.tryParse(p.healthTs!);
    if (t == null) return '-';
    return formatAge(DateTime.now().difference(t));
  }

  @override
  Widget build(BuildContext context) {
    final h = context.watch<DataStore>().health!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('DTN peers seen by ${h.nodeId}',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (h.peers.isEmpty)
              const Text('No peers in beacon range (normal for DTN: sync '
                  'happens whenever nodes meet).')
            else
              DataTable(
                columnSpacing: 20,
                columns: const [
                  DataColumn(label: Text('Node')),
                  DataColumn(label: Text('DTN IP')),
                  DataColumn(label: Text('Beacon')),
                  DataColumn(label: Text('Position')),
                  DataColumn(label: Text('Battery A')),
                  DataColumn(label: Text('Battery B')),
                  DataColumn(label: Text('Info age')),
                ],
                rows: h.peers
                    .map((p) => DataRow(cells: [
                          DataCell(Text(p.nodeId)),
                          DataCell(Text(p.ip)),
                          DataCell(Text(_shortTime(p.lastSeen))),
                          DataCell(Text(p.hasFix
                              ? '${p.lat!.toStringAsFixed(5)}, '
                                  '${p.lon!.toStringAsFixed(5)}'
                              : (p.hasHealth ? 'no fix' : '-'))),
                          DataCell(Row(children: [
                            if (batteryFlowIcon(p.batAMa) != null) ...[
                              Icon(batteryFlowIcon(p.batAMa),
                                  size: 13, color: batteryFlowColor(p.batAMa)),
                              const SizedBox(width: 3),
                            ],
                            Text(batteryLine(p.batAV, p.batAMa)),
                          ])),
                          DataCell(Row(children: [
                            if (batteryFlowIcon(p.batBMa) != null) ...[
                              Icon(batteryFlowIcon(p.batBMa),
                                  size: 13, color: batteryFlowColor(p.batBMa)),
                              const SizedBox(width: 3),
                            ],
                            Text(batteryLine(p.batBV, p.batBMa)),
                          ])),
                          // Separate from the beacon column on purpose: a peer
                          // can be beaconing right now while the position and
                          // battery beside it are minutes old.
                          DataCell(Text(_healthAge(p))),
                        ]))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _DegradedCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final h = context.watch<DataStore>().health!;
    if (h.degradedNodes.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.red.shade900.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.report, color: Colors.redAccent),
                const SizedBox(width: 8),
                Text('DEGRADED nodes (LoRa fallback beacons)',
                    style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            ...h.degradedNodes.map((d) => ListTile(
                  dense: true,
                  title: Text(
                      '${d.nodeId}: Pi down, aux module beaconing (last ${d.ts})'),
                  subtitle: Text([
                    if (d.lat != null)
                      'last GPS ${d.lat!.toStringAsFixed(5)}, ${d.lon!.toStringAsFixed(5)}',
                    if (d.batAV != null) 'bat A ${d.batAV!.toStringAsFixed(2)} V',
                    if (d.batBV != null) 'bat B ${d.batBV!.toStringAsFixed(2)} V',
                  ].join('  |  ')),
                )),
          ],
        ),
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

    final situations = suggestedFor(mission.disasterType);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Push these options to this node?'),
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
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Push')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      // Ask the node what it already holds, then pick a version that beats
      // both it and our own counter. Without this a fresh install, a second
      // operator's laptop, or cleared prefs would produce a rejected push
      // and no clue why.
      var nodeVersion = 0;
      try {
        final current = await app.client.getMissionConfig();
        nodeVersion = (current['version'] as num?)?.toInt() ?? 0;
      } catch (_) {
        // Older node without the endpoint: fall back to our own counter.
      }
      final version = await app.claimPortalConfigVersion(nodeVersion);

      final result = await app.client.pushMissionConfig(buildPortalConfig(
        version: version,
        missionName: mission.missionName,
        disasterType: mission.disasterType,
        situations: situations,
      ));
      messenger.showSnackBar(SnackBar(
          content: Text('${data.health?.nodeId ?? "Node"} is now serving '
              'config v${result['version']}.')));
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('Victim portal options',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 10),
              Chip(
                label: Text(cfg.label),
                visualDensity: VisualDensity.compact,
                backgroundColor:
                    cfg.isStock ? Colors.orange.shade900 : Colors.green.shade900,
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              cfg.isStock
                  ? 'This node serves the built-in need-based options. That '
                      'works, it is just not tailored to this mission.'
                  : 'Serving ${cfg.situationCount} options for '
                      '"${cfg.missionName}".',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            if (!app.isHq)
              Text('HQ login required to change what victims are shown.',
                  style: Theme.of(context).textTheme.bodySmall)
            else
              FilledButton.icon(
                onPressed: _busy ? null : () => _push(context),
                icon: _busy
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload, size: 16),
                label: Text(_busy ? 'Pushing...' : 'Push mission options'),
              ),
          ],
        ),
      ),
    );
  }
}
