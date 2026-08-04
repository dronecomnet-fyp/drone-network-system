/// Which layers the operations map draws (field backlog #13).
///
/// The operator asked for this alongside the degraded-drone work, and the
/// reason is the same: by the time a mission is running, the map carries
/// victim messages, checkins, field reports, rescuers, placements,
/// deployed drones and node positions all at once, and finding the one
/// thing you care about means turning the rest off for a moment.
///
/// Two deliberate choices. Everything starts ON, because a filter someone
/// forgot they set is how a victim goes unseen. And the panel shows a
/// COUNT per layer, so turning something off is an informed decision
/// rather than a guess about what disappeared.
library;

import 'package:flutter/material.dart';

class MapFilters {
  bool victims = true;
  bool checkins = true;
  bool reports = true;
  bool rescuers = true;
  bool placements = true;
  bool fleet = true;
  bool nodes = true;
  bool degraded = true;

  /// The operator's own drawing: GCC position, advance arrows, suspected
  /// areas. Grouped as one layer because they are one thought.
  bool intent = true;

  bool get allOn =>
      intent &&
      victims &&
      checkins &&
      reports &&
      rescuers &&
      placements &&
      fleet &&
      nodes &&
      degraded;

  int get hiddenCount => [
        intent,
        victims,
        checkins,
        reports,
        rescuers,
        placements,
        fleet,
        nodes,
        degraded,
      ].where((on) => !on).length;

  void showAll() {
    victims = checkins = reports = rescuers = true;
    placements = fleet = nodes = degraded = true;
    intent = true;
  }
}

/// The button and its popup. Kept in one widget because the panel has no
/// life of its own: it is a menu attached to a button.
class MapFilterButton extends StatelessWidget {
  const MapFilterButton({
    super.key,
    required this.filters,
    required this.onChanged,
    this.counts = const {},
  });

  final MapFilters filters;
  final VoidCallback onChanged;

  /// Optional per-layer counts, keyed by the same names used below.
  final Map<String, int> counts;

  @override
  Widget build(BuildContext context) {
    final hidden = filters.hiddenCount;
    return Card(
      color: hidden > 0 ? Colors.orange.shade900 : null,
      child: InkWell(
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.layers, size: 18),
              const SizedBox(width: 8),
              // Says what is HIDDEN, not what is shown. A count of visible
              // layers is reassuring noise; a count of hidden ones is a
              // standing reminder that the map is not telling you
              // everything.
              Text(hidden == 0 ? 'Layers' : '$hidden layer(s) hidden'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Widget row(String label, String key, bool value, void Function(bool) set,
              {Color? color}) {
            final n = counts[key];
            return CheckboxListTile(
              dense: true,
              value: value,
              onChanged: (v) {
                set(v ?? true);
                setLocal(() {});
                onChanged();
              },
              secondary: color == null
                  ? null
                  : Icon(Icons.circle, size: 14, color: color),
              title: Text(n == null ? label : '$label  ($n)'),
            );
          }

          return AlertDialog(
            title: const Text('Map layers'),
            content: SizedBox(
              width: 340,
              child: ListView(
                shrinkWrap: true,
                children: [
                  row('Victim messages', 'victims', filters.victims,
                      (v) => filters.victims = v, color: Colors.redAccent),
                  row('Emergency app checkins', 'checkins', filters.checkins,
                      (v) => filters.checkins = v, color: Colors.blueAccent),
                  row('Field reports', 'reports', filters.reports,
                      (v) => filters.reports = v, color: Colors.purpleAccent),
                  row('Rescuers', 'rescuers', filters.rescuers,
                      (v) => filters.rescuers = v, color: Colors.greenAccent),
                  const Divider(),
                  row('Planned placements', 'placements', filters.placements,
                      (v) => filters.placements = v, color: Colors.cyanAccent),
                  row('Deployed drones', 'fleet', filters.fleet,
                      (v) => filters.fleet = v, color: Colors.amberAccent),
                  row('Nodes', 'nodes', filters.nodes,
                      (v) => filters.nodes = v, color: Colors.cyanAccent),
                  row('Degraded drones', 'degraded', filters.degraded,
                      (v) => filters.degraded = v, color: Colors.redAccent),
                  row('GCC, advance arrows, suspected areas', 'intent',
                      filters.intent, (v) => filters.intent = v,
                      color: Colors.amberAccent),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  filters.showAll();
                  setLocal(() {});
                  onChanged();
                },
                child: const Text('Show everything'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}
