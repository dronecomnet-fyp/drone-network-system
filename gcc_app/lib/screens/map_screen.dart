/// Operations Map (file 04 screen 1, the home screen).
///
/// OFFLINE tiles only: no internet exists at a deployment, so tiles come
/// from a pre-mission MBTiles file loaded in Settings (preparation steps:
/// docs/OFFLINE_MAPS.md). Shipping an online-only map would be a spec
/// violation; with no file loaded the map shows a plain grid and a banner.
///
/// Layers: victim messages (red NEW / green CLAIMED), emergency-app
/// checkins (blue dots, orange for SOS), personnel field reports
/// (purple), the connected node (drone icon), DEGRADED nodes at their
/// last beaconed position (red drone icon).
///
/// PLANNING mode: tap to drop named advisory markers with coverage
/// circles; save/load the plan as a local JSON file. Markers never
/// command a drone (file 04: planning is advisory).
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../state/data_store.dart';
import '../state/plan_state.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MbTiles? _mbtiles;
  String _openedPath = '';
  String? _tileError;

  // Sri Lanka centroid as the no-data fallback view.
  static const _fallbackCenter = LatLng(7.8731, 80.7718);

  @override
  void dispose() {
    _mbtiles?.dispose();
    super.dispose();
  }

  void _syncTiles(String path) {
    if (path == _openedPath) return;
    _mbtiles?.dispose();
    _mbtiles = null;
    _tileError = null;
    _openedPath = path;
    if (path.isEmpty) return;
    try {
      _mbtiles = MbTiles(mbtilesPath: path);
    } catch (e) {
      _tileError = 'Could not open MBTiles file: $e';
    }
  }

  LatLng _initialCenter(DataStore data) {
    final meta = _mbtiles?.getMetadata();
    final center = meta?.defaultCenter;
    if (center != null) return LatLng(center.latitude, center.longitude);
    final gps = data.health?.gps;
    if (gps != null && gps.hasFix) return LatLng(gps.lat!, gps.lon!);
    return _fallbackCenter;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = context.watch<DataStore>();
    final plan = context.watch<PlanState>();
    _syncTiles(app.mbtilesPath);

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _initialCenter(data),
            initialZoom: 13,
            onTap: (tapPosition, latlng) {
              if (plan.planningMode) _addPlanMarker(context, latlng);
            },
          ),
          children: [
            if (_mbtiles != null)
              TileLayer(
                tileProvider: MbTilesTileProvider(
                    mbtiles: _mbtiles!, silenceTileNotFound: true),
              ),
            CircleLayer(
              circles: plan.markers
                  .map((m) => CircleMarker(
                        point: LatLng(m.lat, m.lon),
                        radius: m.radiusM,
                        useRadiusInMeter: true,
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderColor: Colors.amber,
                        borderStrokeWidth: 1.5,
                      ))
                  .toList(),
            ),
            MarkerLayer(markers: _buildMarkers(data, plan)),
          ],
        ),
        if (_mbtiles == null)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              color: Colors.orange.shade900,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  _tileError ??
                      'No offline map loaded. Load the mission region '
                          '.mbtiles in Settings (docs/OFFLINE_MAPS.md). '
                          'Pins still render on the blank grid.',
                ),
              ),
            ),
          ),
        Positioned(
          bottom: 12,
          left: 12,
          child: _LegendCard(),
        ),
        Positioned(
          top: _mbtiles == null ? 84 : 12,
          right: 12,
          child: _PlanPanel(
            onSave: () => _savePlan(context),
            onLoad: () => _loadPlan(context),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(DataStore data, PlanState plan) {
    final markers = <Marker>[];

    // Victim messages with a user location.
    for (final m in data.messages.items.where((m) => m.hasUserLocation)) {
      markers.add(Marker(
        point: LatLng(m.userLat!, m.userLon!),
        width: 34,
        height: 34,
        child: Tooltip(
          message:
              '${m.isClaimed ? "CLAIMED by ${m.claimedBy}" : "NEW"}\n${m.content}',
          child: Icon(Icons.location_pin,
              size: 34,
              color: m.isClaimed ? Colors.greenAccent : Colors.redAccent),
        ),
      ));
    }

    // Emergency app checkins.
    for (final c in data.checkins.items) {
      if (c.lat == null || c.lon == null) continue;
      markers.add(Marker(
        point: LatLng(c.lat!, c.lon!),
        width: 14,
        height: 14,
        child: Tooltip(
          message:
              '${c.sos ? "SOS " : ""}checkin ${c.deviceId.substring(0, c.deviceId.length.clamp(0, 8))}\n${c.recordedAt}',
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.sos ? Colors.deepOrange : Colors.lightBlueAccent,
              border: Border.all(color: Colors.black54),
            ),
          ),
        ),
      ));
    }

    // Personnel field reports with a location.
    for (final g in data.gsMessages.items.where((g) => g.hasLocation)) {
      markers.add(Marker(
        point: LatLng(g.locationLat!, g.locationLon!),
        width: 26,
        height: 26,
        child: Tooltip(
          message: 'report by ${g.sender}\n${g.content}',
          child: const Icon(Icons.flag, size: 26, color: Colors.purpleAccent),
        ),
      ));
    }

    // Connected node at its GPS position.
    final gps = data.health?.gps;
    if (gps != null && gps.hasFix) {
      markers.add(Marker(
        point: LatLng(gps.lat!, gps.lon!),
        width: 36,
        height: 36,
        child: Tooltip(
          message: '${data.health!.nodeId} (connected)',
          child: const Icon(Icons.airplanemode_active,
              size: 36, color: Colors.cyanAccent),
        ),
      ));
    }

    // Degraded nodes at their last beaconed position (greyed/red).
    for (final d in data.health?.degradedNodes ?? const []) {
      if (d.lat == null || d.lon == null) continue;
      markers.add(Marker(
        point: LatLng(d.lat!, d.lon!),
        width: 36,
        height: 36,
        child: Tooltip(
          message: '${d.nodeId} DEGRADED (last beacon ${d.ts})',
          child: const Icon(Icons.airplanemode_inactive,
              size: 36, color: Colors.redAccent),
        ),
      ));
    }

    // Planning markers.
    for (final p in plan.markers) {
      markers.add(Marker(
        point: LatLng(p.lat, p.lon),
        width: 120,
        height: 48,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.push_pin, size: 24, color: Colors.amber),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              color: Colors.black54,
              child: Text(p.name,
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ));
    }

    return markers;
  }

  Future<void> _addPlanMarker(BuildContext context, LatLng latlng) async {
    final app = context.read<AppState>();
    final plan = context.read<PlanState>();
    final nameCtrl = TextEditingController(
        text: 'position ${plan.markers.length + 1}');
    final radiusCtrl =
        TextEditingController(text: app.coverageRadiusM.toStringAsFixed(0));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Planning marker'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${latlng.latitude.toStringAsFixed(5)}, '
                '${latlng.longitude.toStringAsFixed(5)}'),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Name', hintText: 'e.g. place drone here'),
            ),
            TextField(
              controller: radiusCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Coverage radius (m)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Add')),
        ],
      ),
    );
    if (confirmed != true) return;
    final radius = double.tryParse(radiusCtrl.text) ?? app.coverageRadiusM;
    plan.addMarker(PlanMarker(
      name: nameCtrl.text.trim().isEmpty ? 'marker' : nameCtrl.text.trim(),
      lat: latlng.latitude,
      lon: latlng.longitude,
      radiusM: radius,
    ));
    await app.updateSettings(newCoverageRadiusM: radius);
  }

  Future<void> _savePlan(BuildContext context) async {
    final plan = context.read<PlanState>();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save operation plan',
      fileName: 'operation_plan.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    final err = await plan.saveToFile(path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Plan saved to $path')));
    }
  }

  Future<void> _loadPlan(BuildContext context) async {
    final plan = context.read<PlanState>();
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Load operation plan',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final err = await plan.loadFromFile(path);
    if (context.mounted && err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

class _PlanPanel extends StatelessWidget {
  final VoidCallback onSave;
  final VoidCallback onLoad;

  const _PlanPanel({required this.onSave, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    final plan = context.watch<PlanState>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Planning'),
                const SizedBox(width: 8),
                Switch(
                  value: plan.planningMode,
                  onChanged: (_) => plan.togglePlanning(),
                ),
              ],
            ),
            if (plan.planningMode) ...[
              Text('tap the map to drop a marker',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  OutlinedButton(onPressed: onSave, child: const Text('Save')),
                  OutlinedButton(onPressed: onLoad, child: const Text('Load')),
                  OutlinedButton(
                    onPressed:
                        plan.markers.isEmpty ? null : () => plan.clear(),
                    child: const Text('Clear'),
                  ),
                ],
              ),
              if (plan.markers.isNotEmpty)
                ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 180, maxWidth: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: plan.markers
                        .map((m) => ListTile(
                              dense: true,
                              title: Text(m.name,
                                  overflow: TextOverflow.ellipsis),
                              subtitle:
                                  Text('${m.radiusM.toStringAsFixed(0)} m'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18),
                                onPressed: () => plan.removeMarker(m),
                              ),
                            ))
                        .toList(),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LegendCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            row(Icons.location_pin, Colors.redAccent, 'victim NEW'),
            row(Icons.location_pin, Colors.greenAccent, 'victim CLAIMED'),
            row(Icons.circle, Colors.lightBlueAccent, 'checkin'),
            row(Icons.circle, Colors.deepOrange, 'SOS checkin'),
            row(Icons.flag, Colors.purpleAccent, 'field report'),
            row(Icons.airplanemode_active, Colors.cyanAccent, 'node (live)'),
            row(Icons.airplanemode_inactive, Colors.redAccent,
                'node DEGRADED'),
            row(Icons.push_pin, Colors.amber, 'plan marker'),
          ],
        ),
      ),
    );
  }
}
