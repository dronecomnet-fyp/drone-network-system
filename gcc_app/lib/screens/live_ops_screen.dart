/// Live Operations (M7a): the numbers dashboard for a running mission.
///
/// Pure consumer of DataStore (5 s poll). Every figure carries its data
/// age, because in a DTN mesh "live" honestly means "as last synced":
/// remote-node data is only as fresh as beacons + sync hops.
///
/// The Map tab stays the map; this tab answers "how is the operation
/// going right now" at a glance: victims, SOS, rescuers, field reports,
/// mesh health, and (M7f) the fleet board.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/data_store.dart';
import 'fleet_board.dart';

class LiveOpsScreen extends StatelessWidget {
  const LiveOpsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final app = context.watch<AppState>();
    final h = data.health;

    final newCount =
        data.messages.items.where((m) => m.status == 'NEW').length;
    final claimedCount =
        data.messages.items.where((m) => m.status == 'CLAIMED').length;
    final sosCount = data.checkins.items.where((c) => c.sos).length;
    final activePersonnel =
        data.personnel.items.where((p) => p.isActive).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Live Operations',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(width: 12),
            Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor:
                  data.isConnected ? Colors.green.shade900 : Colors.red.shade900,
              label: Text(data.isConnected
                  ? 'LIVE via ${h?.nodeId ?? "node"}'
                  : 'NO NODE IN RANGE'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'All figures show their own data age. Remote nodes are as fresh '
          'as DTN sync plus beacons, never assumed live.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        if (data.lastError != null)
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(data.lastError!),
            ),
          ),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatTile(
              label: 'VICTIM MESSAGES',
              value: '$newCount NEW',
              sub: '$claimedCount claimed',
              age: data.messages.age,
              accent: newCount > 0 ? Colors.redAccent : Colors.greenAccent,
            ),
            _StatTile(
              label: 'SOS',
              value: '$sosCount',
              sub: '${data.checkins.items.length} check-ins total',
              age: data.checkins.age,
              accent: sosCount > 0 ? Colors.deepOrangeAccent : Colors.white70,
            ),
            _StatTile(
              label: 'FIELD REPORTS',
              value: '${data.gsMessages.items.length}',
              sub: 'from rescue teams',
              age: data.gsMessages.age,
            ),
            _StatTile(
              label: 'RESCUERS TRACKED',
              value: '${data.personnelLocations.items.length}',
              sub: 'sharing location',
              age: data.personnelLocations.age,
            ),
            _StatTile(
              label: 'PERSONNEL',
              value: app.isHq ? '$activePersonnel active' : 'HQ only',
              sub: app.isHq
                  ? '${data.personnel.items.length} issued'
                  : 'log in as HQ to view',
              age: app.isHq ? data.personnel.age : null,
            ),
            _StatTile(
              label: 'MESH',
              value: h == null
                  ? 'offline'
                  : '${h.peers.length + 1} node${h.peers.isEmpty ? "" : "s"}',
              sub: h == null
                  ? 'join a RESCUE_x WiFi'
                  : (h.degradedNodes.isEmpty
                      ? 'no degraded nodes'
                      : '${h.degradedNodes.length} DEGRADED'),
              age: data.healthUpdated == null
                  ? null
                  : DateTime.now().difference(data.healthUpdated!),
              accent: (h?.degradedNodes.isNotEmpty ?? false)
                  ? Colors.redAccent
                  : null,
            ),
            _StatTile(
              label: 'NODE BATTERY',
              value: h?.battery.aV == null
                  ? 'n/a'
                  : '${h!.battery.aV!.toStringAsFixed(2)} V',
              sub: h?.battery.bV == null
                  ? (h?.aux == 'absent' ? 'no aux module' : 'B: n/a')
                  : 'B: ${h!.battery.bV!.toStringAsFixed(2)} V',
              age: data.healthUpdated == null
                  ? null
                  : DateTime.now().difference(data.healthUpdated!),
            ),
            _StatTile(
              label: 'NODE GPS',
              value: (h?.gps.hasFix ?? false) ? 'fix' : 'no fix',
              sub: (h?.gps.hasFix ?? false)
                  ? '${h!.gps.lat!.toStringAsFixed(4)}, ${h.gps.lon!.toStringAsFixed(4)} (${h.gps.sats} sats)'
                  : 'position from last known',
              age: data.healthUpdated == null
                  ? null
                  : DateTime.now().difference(data.healthUpdated!),
              accent: (h?.gps.hasFix ?? false) ? null : Colors.orangeAccent,
            ),
            _StatTile(
              label: 'CLOCK',
              value: h?.clockSource ?? 'unknown',
              sub: h?.clockSource == 'gps'
                  ? 'GPS-synced timestamps'
                  : 'timestamps approximate',
              age: null,
              accent: h?.clockSource == 'gps' ? null : Colors.orangeAccent,
            ),
          ],
        ),
        const SizedBox(height: 16),
        const FleetBoard(),
        const SizedBox(height: 16),
        _RescuersCard(),
        const SizedBox(height: 16),
        _NodesTable(),
      ],
    );
  }
}

/// Rescuers sharing their location (M7d), each with how fresh it is.
class _RescuersCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final locs = data.personnelLocations.items;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Rescuers', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                Text('list ${formatAge(data.personnelLocations.age)}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 4),
            if (locs.isEmpty)
              const Text('No rescuers sharing location yet. The rescue app '
                  'sends a heartbeat while logged in and in the foreground.')
            else
              ...locs.map((l) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_pin_circle,
                        color: Colors.tealAccent),
                    title: Text(l.personnelId),
                    subtitle: Text([
                      if (l.hasLocation)
                        '${l.lat!.toStringAsFixed(5)}, ${l.lon!.toStringAsFixed(5)}',
                      if (l.batteryPct != null) 'battery ${l.batteryPct}%',
                      'updated ${l.updatedAt}',
                    ].join('  |  ')),
                  )),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Duration? age;
  final Color? accent;

  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
    this.age,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
        width: 190,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white54,
                    letterSpacing: 0.8)),
            const SizedBox(height: 6),
            Text(value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: accent, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(sub, style: Theme.of(context).textTheme.bodySmall),
            if (age != null) ...[
              const SizedBox(height: 6),
              Text(formatAge(age),
                  style: const TextStyle(fontSize: 10, color: Colors.white38)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Every node the operation knows about in one table: the connected node
/// (live), its beacon peers (as last seen), and degraded nodes heard only
/// through LoRa fallback beacons.
class _NodesTable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final h = data.health;
    if (h == null) return const SizedBox.shrink();

    final rows = <DataRow>[
      DataRow(cells: [
        DataCell(Text(h.nodeId,
            style: const TextStyle(fontWeight: FontWeight.w600))),
        DataCell(Chip(
          label: const Text('CONNECTED'),
          visualDensity: VisualDensity.compact,
          backgroundColor: Colors.green.shade900,
        )),
        DataCell(Text(h.gps.hasFix
            ? '${h.gps.lat!.toStringAsFixed(5)}, ${h.gps.lon!.toStringAsFixed(5)}'
            : 'no fix')),
        DataCell(Text(h.battery.aV == null
            ? 'n/a'
            : '${h.battery.aV!.toStringAsFixed(2)} V')),
        DataCell(Text(data.healthUpdated == null
            ? 'never'
            : formatAge(DateTime.now().difference(data.healthUpdated!)))),
      ]),
      ...h.peers.map((p) => DataRow(cells: [
            DataCell(Text(p.nodeId)),
            DataCell(Chip(
              label: const Text('PEER'),
              visualDensity: VisualDensity.compact,
            )),
            const DataCell(Text('via mesh')),
            const DataCell(Text('-')),
            DataCell(Text(p.lastSeen)),
          ])),
      ...h.degradedNodes.map((d) => DataRow(cells: [
            DataCell(Text(d.nodeId,
                style: const TextStyle(color: Colors.redAccent))),
            DataCell(Chip(
              label: const Text('DEGRADED'),
              visualDensity: VisualDensity.compact,
              backgroundColor: Colors.red.shade900,
            )),
            DataCell(Text(d.lat != null
                ? '${d.lat!.toStringAsFixed(5)}, ${d.lon!.toStringAsFixed(5)}'
                : 'unknown')),
            DataCell(Text(d.batAV == null
                ? 'n/a'
                : '${d.batAV!.toStringAsFixed(2)} V')),
            DataCell(Text(d.ts)),
          ])),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Known nodes', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Node')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Position')),
                  DataColumn(label: Text('Battery')),
                  DataColumn(label: Text('Last seen')),
                ],
                rows: rows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
