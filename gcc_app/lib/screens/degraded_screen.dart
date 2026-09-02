/// Degraded drones and the LoRa log (field backlog #13).
///
/// The operator asked for "a tab for degraded drones that logs every LoRa
/// message". The reason it needs its own tab, rather than a line in Nodes,
/// is that /health only ever answers ONE question: is that drone down
/// right now. Standing in a field deciding whether to walk half a
/// kilometre to a drone, the questions are different: what did it last
/// tell us, is the signal getting stronger or weaker, was it still
/// carrying an unsent victim message, and is it recovering on its own.
///
/// Three things are shown, in that order of urgency:
///
///  1. Nodes currently degraded, with the last position they beaconed.
///  2. Nodes that RECOVERED, kept visible for a while afterwards, because
///     "it came back by itself" is information the operator acts on
///     (they stop walking) and silently dropping the row hides it.
///  3. The raw LoRa log, filterable, because when the summary looks wrong
///     the operator needs to see what actually arrived.
///
/// The log is fleet-wide: lora_events replicate, so a beacon heard by the
/// drone nearest the failure shows here even when the GCC is joined to a
/// different one.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../main.dart' show ShellNav;
import '../state/data_store.dart';
import '../widgets/blinking.dart';

class DegradedScreen extends StatefulWidget {
  const DegradedScreen({super.key});

  @override
  State<DegradedScreen> createState() => _DegradedScreenState();
}

class _DegradedScreenState extends State<DegradedScreen> {
  /// Empty means every node. Set by tapping a node card, so the log
  /// narrows to the drone the operator is thinking about.
  String _nodeFilter = '';

  /// Fallback beacons only, by default. Everything else the radio hears is
  /// noise to an operator, and burying six beacons in two hundred lines of
  /// it defeats the point of the tab.
  bool _fallbackOnly = true;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<DataStore>();
    final degraded = data.health?.degradedNodes ?? const <DegradedNode>[];
    final events = data.loraEvents.items;

    final degradedIds = degraded.map((d) => d.nodeId).toSet();
    final recovered = <String, LoraEvent>{};
    for (final e in events) {
      if (!e.isFallback || e.aboutNode.isEmpty) continue;
      if (degradedIds.contains(e.aboutNode)) continue;
      if (_ageOf(e.receivedAt) > const Duration(hours: 1)) continue;
      recovered.putIfAbsent(e.aboutNode, () => e);
    }

    final shown = events.where((e) {
      if (_fallbackOnly && !e.isFallback) return false;
      if (_nodeFilter.isNotEmpty && e.aboutNode != _nodeFilter) return false;
      return true;
    }).toList();

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Command-center header ──
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0F0A),
              border: Border(
                bottom: BorderSide(
                    color: Colors.white.withOpacity(0.08), width: 1),
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
                            color: degraded.isNotEmpty
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (degraded.isNotEmpty
                                        ? Colors.redAccent
                                        : Colors.greenAccent)
                                    .withOpacity(0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'DEGRADED DRONES',
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
                      data.loraEvents.age == null
                          ? 'LoRa log never loaded'
                          : '${degraded.length} degraded  ·  ${recovered.length} recovered  ·  log ${_short(data.loraEvents.age!)} old',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white38,
                          letterSpacing: 0.3),
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
                // Status banner
                if (degraded.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.greenAccent.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            color: Colors.greenAccent, size: 20),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'All drones healthy',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Colors.greenAccent,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Every node the fleet can see is answering normally.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  for (final d in degraded) _degradedCard(d, events),

                // Recovered section
                if (recovered.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.restore, size: 15, color: Colors.greenAccent),
                      const SizedBox(width: 8),
                      const Text(
                        'RECOVERED',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.greenAccent,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                            height: 1,
                            color: Colors.white.withOpacity(0.07)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final e in recovered.values)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.greenAccent.withOpacity(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle,
                              color: Colors.greenAccent, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  e.aboutNode,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'Last beacon ${_short(_ageOf(e.receivedAt))} ago  ·  answering normally now',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white54),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                // LoRa log section
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.radio, size: 15, color: Colors.orangeAccent),
                    const SizedBox(width: 8),
                    const Text(
                      'LORA LOG',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.orangeAccent,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                          height: 1,
                          color: Colors.white.withOpacity(0.07)),
                    ),
                    const SizedBox(width: 12),
                    FilterChip(
                      label: const Text('Fallback only',
                          style: TextStyle(fontSize: 12)),
                      selected: _fallbackOnly,
                      onSelected: (v) => setState(() => _fallbackOnly = v),
                      selectedColor: Colors.orangeAccent.withOpacity(0.2),
                      checkmarkColor: Colors.orangeAccent,
                      side: BorderSide(
                          color: Colors.orangeAccent.withOpacity(0.4)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 0),
                    ),
                    if (_nodeFilter.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      InputChip(
                        label: Text(_nodeFilter,
                            style: const TextStyle(fontSize: 12)),
                        onDeleted: () =>
                            setState(() => _nodeFilter = ''),
                        side: BorderSide(
                            color: Colors.white.withOpacity(0.2)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                if (shown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Nothing logged yet. An empty log means the radio has heard nothing, which is the normal state when every drone is healthy.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.07)),
                    ),
                    child: Column(
                      children: [
                        for (int i = 0;
                            i < shown.take(200).length;
                            i++) ...[
                          if (i > 0)
                            Divider(
                                height: 1,
                                color: Colors.white.withOpacity(0.05)),
                          _logRow(shown[i]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _degradedCard(DegradedNode d, List<LoraEvent> events) {
    final mine = events
        .where((e) => e.isFallback && e.aboutNode == d.nodeId)
        .toList();
    final latest = mine.isEmpty ? null : mine.first;
    final heardBy = mine.map((e) => e.heardBy).toSet();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.redAccent.withOpacity(0.45)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Blinking(
                  child: Icon(Icons.airplanemode_inactive,
                      size: 22, color: Colors.redAccent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.nodeId,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.redAccent,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Text(
                      'Pi not answering  ·  aux module beaconing over LoRa',
                      style: TextStyle(fontSize: 11, color: Colors.white54),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.map_outlined, size: 15),
                label: const Text('Map', style: TextStyle(fontSize: 12)),
                onPressed: () =>
                    context.read<ShellNav>().go(ShellNav.mapTab),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Facts grid — 3 columns
          Row(
            children: [
              Expanded(
                  child: _fact(
                      'LAST BEACON',
                      latest == null
                          ? d.ts
                          : '${_short(_ageOf(latest.receivedAt))} ago',
                      Icons.access_time,
                      Colors.orangeAccent)),
              const SizedBox(width: 8),
              Expanded(
                  child: _fact(
                      'POSITION',
                      d.lat == null || d.lon == null
                          ? 'never sent one'
                          : '${d.lat!.toStringAsFixed(5)}, ${d.lon!.toStringAsFixed(5)}',
                      Icons.location_on_outlined,
                      Colors.white54)),
              const SizedBox(width: 8),
              Expanded(
                  child: _fact(
                      'HEARD BY',
                      heardBy.isEmpty ? 'this node' : heardBy.join(', '),
                      Icons.cell_tower,
                      Colors.cyanAccent)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                  child: _fact(
                      'SIGNAL',
                      latest?.rssi == null
                          ? 'unknown'
                          : '${latest!.rssi!.toStringAsFixed(0)} dBm'
                              '${latest.snr == null ? "" : " / SNR ${latest.snr!.toStringAsFixed(1)}"}',
                      Icons.signal_cellular_alt,
                      Colors.purpleAccent)),
              const SizedBox(width: 8),
              Expanded(
                  child: _fact(
                      'BATTERY',
                      latest?.batAV == null
                          ? 'unknown'
                          : '${latest!.batAV!.toStringAsFixed(2)} V'
                              '${latest.batBV == null ? "" : " / ${latest.batBV!.toStringAsFixed(2)} V"}',
                      Icons.battery_charging_full_outlined,
                      Colors.yellowAccent)),
              const SizedBox(width: 8),
              Expanded(
                  child: _fact('BEACONS', '${mine.length}',
                      Icons.broadcast_on_personal_outlined,
                      Colors.white54)),
            ],
          ),

          // Last victim message
          if (latest != null && latest.lastMsg.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.message_outlined,
                          size: 13, color: Colors.white38),
                      SizedBox(width: 6),
                      Text(
                        'LAST VICTIM MESSAGE ON THIS NODE',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: Colors.white38,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(latest.lastMsg,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white)),
                  const SizedBox(height: 4),
                  const Text(
                    'The beacon carries only the newest cached message. Others may still be on the drone.',
                    style: TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() => _nodeFilter = d.nodeId),
            child: Row(
              children: [
                const Icon(Icons.filter_list,
                    size: 14, color: Colors.orangeAccent),
                const SizedBox(width: 6),
                const Text(
                  'Filter LoRa log to this drone',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fact(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: color.withOpacity(0.7)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: color.withOpacity(0.7),
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _logRow(LoraEvent e) {
    final isFallback = e.isFallback;
    final color = isFallback ? Colors.redAccent : Colors.white54;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isFallback ? Icons.warning_amber : Icons.radio,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isFallback
                      ? '${e.aboutNode}  ·  fallback beacon'
                      : 'LoRa frame (unattributed)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isFallback ? Colors.redAccent : Colors.white70,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_short(_ageOf(e.receivedAt))} ago  ·  heard by ${e.heardBy}'
                  '${e.rssi == null ? "" : "  ·  ${e.rssi!.toStringAsFixed(0)} dBm"}'
                  '${e.lastMsg.isEmpty ? "" : "\ncarrying: ${e.lastMsg}"}',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white54),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.code, size: 14, color: Colors.white24),
            tooltip: 'Raw frame',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Raw LoRa frame'),
                content:
                    SelectableText(e.raw.isEmpty ? '(empty)' : e.raw),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Duration _ageOf(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return const Duration(days: 999);
  return DateTime.now().toUtc().difference(t.toUtc());
}

String _short(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 48) return '${d.inHours}h';
  return '${d.inDays}d';
}
