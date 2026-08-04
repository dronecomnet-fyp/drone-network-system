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

    // Nodes that beaconed at some point but are not degraded now. Kept for
    // an hour: long enough that the operator sees a recovery they were not
    // watching for, short enough that yesterday's incident is not still on
    // screen.
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Text('Degraded drones',
                  style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              Text(
                data.loraEvents.age == null
                    ? 'log never loaded'
                    : 'log ${_short(data.loraEvents.age!)} old',
                style: const TextStyle(fontSize: 12, color: Colors.white54),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'A drone appears here when its Pi stops answering and its aux '
            'module starts beaconing over LoRa. The aux module keeps '
            'reporting for as long as it has power, which is how a drone '
            'that has otherwise gone silent still tells you where it is.',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          if (degraded.isEmpty)
            Card(
              color: Colors.green.shade900,
              child: const ListTile(
                leading: Icon(Icons.check_circle),
                title: Text('No drone is currently degraded'),
                subtitle: Text(
                    'Every node the fleet can see is answering normally.'),
              ),
            )
          else
            for (final d in degraded) _degradedCard(d, events),
          if (recovered.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Recovered', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              'These beaconed earlier and are answering again. The aux '
              'module returns to normal by itself after three consecutive '
              'pings from the Pi, so a node that recovers needs no action.',
              style: TextStyle(fontSize: 12, color: Colors.white54),
            ),
            const SizedBox(height: 8),
            for (final e in recovered.values)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check, color: Colors.greenAccent),
                  title: Text(e.aboutNode),
                  subtitle: Text(
                      'last beacon ${_short(_ageOf(e.receivedAt))} ago, '
                      'answering normally now'),
                ),
              ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Text('LoRa log',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(width: 16),
              FilterChip(
                label: const Text('Fallback beacons only'),
                selected: _fallbackOnly,
                onSelected: (v) => setState(() => _fallbackOnly = v),
              ),
              const SizedBox(width: 8),
              if (_nodeFilter.isNotEmpty)
                InputChip(
                  label: Text(_nodeFilter),
                  onDeleted: () => setState(() => _nodeFilter = ''),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Nothing logged yet. An empty log means the radio has heard '
                'nothing, which is the normal state when every drone is '
                'healthy.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final e in shown.take(200)) _logRow(e),
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

    return Card(
      color: Colors.red.shade900,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Blinking(
                  child: Icon(Icons.airplanemode_inactive,
                      size: 30, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Text(d.nodeId,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(width: 12),
                const Text('Pi not answering, aux module beaconing'),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.map, size: 16),
                  label: const Text('Show on map'),
                  onPressed: () =>
                      context.read<ShellNav>().go(ShellNav.mapTab),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 24,
              runSpacing: 8,
              children: [
                _fact('Last beacon',
                    latest == null
                        ? d.ts
                        : '${_short(_ageOf(latest.receivedAt))} ago'),
                _fact('Position',
                    d.lat == null || d.lon == null
                        ? 'never sent one'
                        : '${d.lat!.toStringAsFixed(5)}, '
                            '${d.lon!.toStringAsFixed(5)}'),
                // Two receivers is better evidence than one, and it also
                // tells the operator the beacon is genuinely radiating
                // rather than one node hallucinating.
                _fact('Heard by',
                    heardBy.isEmpty ? 'this node' : heardBy.join(', ')),
                _fact('Signal',
                    latest?.rssi == null
                        ? 'unknown'
                        : '${latest!.rssi!.toStringAsFixed(0)} dBm'
                            '${latest.snr == null ? "" : " / SNR ${latest.snr!.toStringAsFixed(1)}"}'),
                _fact('Battery',
                    latest?.batAV == null
                        ? 'unknown'
                        : '${latest!.batAV!.toStringAsFixed(2)} V'
                            '${latest.batBV == null ? "" : " / ${latest.batBV!.toStringAsFixed(2)} V"}'),
                _fact('Beacons logged', '${mine.length}'),
              ],
            ),
            if (latest != null && latest.lastMsg.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: Colors.black26,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Last victim message it was carrying',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(latest.lastMsg),
                    const SizedBox(height: 4),
                    // The honest caveat. The beacon carries ONE message,
                    // and only the newest one the module had cached.
                    const Text(
                      'The beacon carries only the newest message that node '
                      'had cached. Anything else it was holding is still on '
                      'the drone.',
                      style: TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _nodeFilter = d.nodeId),
              child: const Text('Filter the log to this drone'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: Colors.white70)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _logRow(LoraEvent e) {
    return ListTile(
      dense: true,
      leading: Icon(
        e.isFallback ? Icons.warning_amber : Icons.radio,
        color: e.isFallback ? Colors.redAccent : Colors.white54,
        size: 20,
      ),
      title: Text(
        e.isFallback
            ? '${e.aboutNode} fallback beacon'
            : 'LoRa frame (unattributed)',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(
        '${_short(_ageOf(e.receivedAt))} ago, heard by ${e.heardBy}'
        '${e.rssi == null ? "" : ", ${e.rssi!.toStringAsFixed(0)} dBm"}'
        '${e.lastMsg.isEmpty ? "" : "\ncarrying: ${e.lastMsg}"}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.code, size: 16),
        tooltip: 'Show the raw frame',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Raw LoRa frame'),
            content: SelectableText(e.raw.isEmpty ? '(empty)' : e.raw),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
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
