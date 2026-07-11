/// Nodes (file 04 screen 3): health of the CONNECTED node from /health,
/// its alive-peer table, and DEGRADED nodes learned from LoRa fallback
/// beacons. Every block carries a last-updated age; remote nodes are only
/// as fresh as DTN sync plus beacons (file 04 connectivity model).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/data_store.dart';

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
                _stat('Battery A',
                    bat.aV == null
                        ? 'n/a'
                        : '${bat.aV!.toStringAsFixed(2)} V  ${bat.aMa?.toStringAsFixed(0) ?? "-"} mA'),
                _stat('Battery B',
                    bat.bV == null
                        ? 'n/a'
                        : '${bat.bV!.toStringAsFixed(2)} V  ${bat.bMa?.toStringAsFixed(0) ?? "-"} mA'),
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
      {bool warn = false, String warnText = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white54)),
        Row(
          children: [
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
                columns: const [
                  DataColumn(label: Text('Node')),
                  DataColumn(label: Text('DTN IP')),
                  DataColumn(label: Text('Last seen')),
                ],
                rows: h.peers
                    .map((p) => DataRow(cells: [
                          DataCell(Text(p.nodeId)),
                          DataCell(Text(p.ip)),
                          DataCell(Text(p.lastSeen)),
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
