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

import '../main.dart' show ShellNav;
import '../state/app_state.dart';
import '../state/data_store.dart';
import '../state/drone_controller.dart';
import '../widgets/battery_text.dart';
import '../widgets/degraded_alert.dart';
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
                          color: data.isConnected
                              ? Colors.greenAccent
                              : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: (data.isConnected
                                      ? Colors.greenAccent
                                      : Colors.redAccent)
                                  .withOpacity(0.6),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'LIVE OPERATIONS',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: data.isConnected
                              ? Colors.green.withOpacity(0.15)
                              : Colors.red.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: data.isConnected
                                ? Colors.greenAccent.withOpacity(0.5)
                                : Colors.redAccent.withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          data.isConnected
                              ? 'LIVE via ${h?.nodeId ?? "node"}'
                              : 'NO NODE IN RANGE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: data.isConnected
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'All figures show their own data age. Remote nodes are as fresh as DTN sync plus beacons.',
                    style: TextStyle(
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
              const DegradedAlert(),
              if (data.lastError != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.redAccent, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(data.lastError!,
                            style: const TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                  ),
                ),

              // ── Stats grid ──
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatTile(
                    label: 'VICTIM MESSAGES',
                    icon: Icons.mark_email_unread_outlined,
                    value: '$newCount NEW',
                    sub: '$claimedCount claimed (tap to view)',
                    age: data.messages.age,
                    accent: newCount > 0 ? Colors.redAccent : Colors.greenAccent,
                    onTap: () => context
                        .read<ShellNav>()
                        .goToLiveFeed(source: 'VICTIMS'),
                  ),
                  _StatTile(
                    label: 'SOS',
                    icon: Icons.sos,
                    value: '$sosCount',
                    sub:
                        '${data.checkins.items.length} check-ins total',
                    age: data.checkins.age,
                    accent: sosCount > 0
                        ? Colors.deepOrangeAccent
                        : Colors.white70,
                  ),
                  _StatTile(
                    label: 'FIELD REPORTS',
                    icon: Icons.flag_outlined,
                    value: '${data.gsMessages.items.length}',
                    sub: 'from rescue teams (tap to view)',
                    age: data.gsMessages.age,
                    accent: data.gsMessages.items.isNotEmpty
                        ? Colors.purpleAccent
                        : null,
                    onTap: () => context
                        .read<ShellNav>()
                        .goToLiveFeed(source: 'REPORTS'),
                  ),
                  _StatTile(
                    label: 'RESCUERS TRACKED',
                    icon: Icons.people_outline,
                    value:
                        '${data.personnelLocations.items.length}',
                    sub: 'sharing location',
                    age: data.personnelLocations.age,
                  ),
                  _StatTile(
                    label: 'PERSONNEL',
                    icon: Icons.badge_outlined,
                    value: app.isHq
                        ? '$activePersonnel active'
                        : 'HQ only',
                    sub: app.isHq
                        ? '${data.personnel.items.length} issued'
                        : 'log in as HQ to view',
                    age: app.isHq ? data.personnel.age : null,
                  ),
                  _StatTile(
                    label: 'MESH',
                    icon: Icons.hub_outlined,
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
                    icon: Icons.battery_charging_full_outlined,
                    value: h == null
                        ? 'n/a'
                        : batteryLine(h.battery.aV, h.battery.aMa),
                    sub: h == null ||
                            (h.battery.bV == null &&
                                h.battery.bMa == null)
                        ? (h?.aux == 'absent'
                            ? 'no aux module'
                            : 'B: n/a')
                        : 'B: ${batteryLine(h.battery.bV, h.battery.bMa)}',
                    age: data.healthUpdated == null
                        ? null
                        : DateTime.now().difference(data.healthUpdated!),
                  ),
                  _StatTile(
                    label: 'NODE GPS',
                    icon: Icons.gps_fixed,
                    value: (h?.gps.hasFix ?? false) ? 'fix' : 'no fix',
                    sub: (h?.gps.hasFix ?? false)
                        ? '${h!.gps.lat!.toStringAsFixed(4)}, ${h.gps.lon!.toStringAsFixed(4)} (${h.gps.sats} sats)'
                        : 'position from last known',
                    age: data.healthUpdated == null
                        ? null
                        : DateTime.now().difference(data.healthUpdated!),
                    accent: (h?.gps.hasFix ?? false)
                        ? null
                        : Colors.orangeAccent,
                  ),
                  _StatTile(
                    label: 'CLOCK',
                    icon: Icons.access_time,
                    value: h?.clockSource ?? 'unknown',
                    sub: h?.clockSource == 'gps'
                        ? 'GPS-synced timestamps'
                        : 'timestamps approximate',
                    age: null,
                    accent: h?.clockSource == 'gps'
                        ? null
                        : Colors.orangeAccent,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _SystemDroneCard(),
              const SizedBox(height: 16),
              // ── Fleet & Rescuers side by side ──
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Expanded(child: FleetBoard()),
                    const SizedBox(width: 12),
                    Expanded(child: _RescuersCard()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _NodesTable(),
            ],
          ),
        ),
      ],
    );
  }
}

/// The system drone's own live telemetry over MAVLink (task B). This is
/// separate from node /health: when the operator controls DRONE_S over the
/// relay path they are polling a volunteer node's /health, so the drone's
/// battery and GPS only exist here, on the live control link. Shown whenever
/// the drone link is connected.
class _SystemDroneCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneController>();
    if (!drone.connected) return const SizedBox.shrink();
    final t = drone.telemetry;
    final fresh = drone.linkFresh;
    final age = drone.sinceHeartbeat;
    return Card(
      color: fresh ? null : Colors.red.shade900.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flight, color: Colors.pinkAccent),
                const SizedBox(width: 8),
                Text('System drone (live MAVLink)',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                Chip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor:
                      fresh ? Colors.green.shade900 : Colors.red.shade900,
                  label: Text(fresh
                      ? 'LINK LIVE'
                      : age == null
                          ? 'no heartbeat'
                          : 'stale ${age.inSeconds}s'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'The drone\'s own battery and GPS over the control link, shown '
              'no matter which node the dashboard is polling.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                _dstat('State', t.armed ? 'ARMED' : 'disarmed',
                    color: t.armed ? Colors.redAccent : Colors.greenAccent),
                _dstat('Mode', t.modeName),
                _dstat(
                    'Battery',
                    t.batteryVolts == null
                        ? 'n/a'
                        : '${t.batteryVolts!.toStringAsFixed(2)} V'
                            '${t.batteryRemaining != null && t.batteryRemaining! >= 0 ? "  ${t.batteryRemaining}%" : ""}'),
                _dstat(
                    'GPS',
                    t.hasGpsFix
                        ? '3D fix, ${t.satellites} sats'
                        : 'no fix (${t.satellites} sats)',
                    color: t.hasGpsFix ? null : Colors.orangeAccent),
                if (t.lat != null)
                  _dstat('Position',
                      '${t.lat!.toStringAsFixed(5)}, ${t.lon!.toStringAsFixed(5)}'),
                if (t.relAltM != null)
                  _dstat('Alt', '${t.relAltM!.toStringAsFixed(1)} m'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _dstat(String label, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 11, color: Colors.white54)),
          Text(value,
              style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      );
}

/// Rescuers sharing their location (M7d), each with how fresh it is.
class _RescuersCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final locs = data.personnelLocations.items;
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
              const Icon(Icons.people_outline, size: 16, color: Colors.tealAccent),
              const SizedBox(width: 8),
              const Text(
                'Rescuers',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'last ${formatAge(data.personnelLocations.age)}',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (locs.isEmpty)
            const Text(
              'No rescuers sharing location yet. The rescue app sends a heartbeat while logged in and in the foreground.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            )
          else
            ...locs.map((l) => Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.tealAccent.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_pin_circle,
                          color: Colors.tealAccent, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l.personnelId,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                if (l.hasLocation)
                                  '${l.lat!.toStringAsFixed(5)}, ${l.lon!.toStringAsFixed(5)}',
                                if (l.batteryPct != null)
                                  'battery ${l.batteryPct}%',
                                'updated ${l.updatedAt}',
                              ].join('  ·  '),
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white54),
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

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String sub;
  final Duration? age;
  final Color? accent;
  final VoidCallback? onTap;
  final IconData? icon;

  const _StatTile({
    required this.label,
    required this.value,
    required this.sub,
    this.age,
    this.accent,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = accent ?? Colors.white54;
    final content = Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accent != null
              ? accent!.withOpacity(0.3)
              : Colors.white.withOpacity(0.08),
          width: accent != null ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: accentColor.withOpacity(0.7)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white38,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                const Icon(Icons.open_in_new, size: 11, color: Colors.white24),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: accent ?? Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            style: const TextStyle(fontSize: 11, color: Colors.white54),
          ),
          if (age != null) ...[
            const SizedBox(height: 8),
            Text(
              formatAge(age),
              style: const TextStyle(fontSize: 10, color: Colors.white24),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          child: content,
        ),
      );
    }

    return content;
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
        DataCell(Text(batteryLine(h.battery.aV, h.battery.aMa))),
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
              const Icon(Icons.router_outlined, size: 16, color: Colors.orangeAccent),
              const SizedBox(width: 8),
              const Text(
                'Known Nodes',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
                letterSpacing: 0.8,
              ),
              dataTextStyle: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
              columnSpacing: 28,
              columns: const [
                DataColumn(label: Text('NODE')),
                DataColumn(label: Text('STATUS')),
                DataColumn(label: Text('POSITION')),
                DataColumn(label: Text('BATTERY')),
                DataColumn(label: Text('LAST SEEN')),
              ],
              rows: rows,
            ),
          ),
        ],
      ),
    );
  }
}
