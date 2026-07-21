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
import '../state/fleet_state.dart';
import '../state/mission_state.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MbTiles? _mbtiles;
  String _openedPath = '';
  String? _tileError;

  // When a placement is selected in the panel, the next map tap MOVES it
  // (flutter_map has no native marker drag).
  DronePlacement? _selected;

  // Sri Lanka centroid as the no-data fallback view.
  static const _fallbackCenter = LatLng(7.8731, 80.7718);

  Color _roleColor(String role) {
    switch (role) {
      case kRoleMeshRelay:
        return Colors.cyanAccent;
      case kRoleSystemDrone:
        return Colors.pinkAccent;
      default:
        return Colors.amber;
    }
  }

  Color _fleetPhaseColor(FleetPhase p) {
    switch (p) {
      case FleetPhase.onStation:
        return Colors.greenAccent;
      case FleetPhase.returning:
        return Colors.orangeAccent;
      case FleetPhase.fallback:
        return Colors.deepOrange;
      case FleetPhase.lost:
        return Colors.redAccent;
      default:
        return Colors.amberAccent;
    }
  }

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
    final mission = context.watch<MissionState>();
    final fleet = context.watch<FleetState>();
    _syncTiles(app.mbtilesPath);

    final active = mission.activeDeployment;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: _initialCenter(data),
            initialZoom: 13,
            onTap: (tapPosition, latlng) => _onMapTap(context, mission, latlng),
          ),
          children: [
            if (_mbtiles != null)
              TileLayer(
                tileProvider: MbTilesTileProvider(
                    mbtiles: _mbtiles!, silenceTileNotFound: true),
              ),
            if (mission.area.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: mission.area
                        .map((p) => LatLng(p.lat, p.lon))
                        .toList(),
                    color: Colors.lightBlue.withValues(alpha: 0.10),
                    borderColor: Colors.lightBlueAccent,
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            CircleLayer(
              circles: [
                for (final p in active?.placements ?? const <DronePlacement>[])
                  CircleMarker(
                    point: LatLng(p.lat, p.lon),
                    radius: p.radiusM,
                    useRadiusInMeter: true,
                    color: _roleColor(p.role).withValues(alpha: 0.12),
                    borderColor: _roleColor(p.role),
                    borderStrokeWidth: p == _selected ? 3 : 1.5,
                  ),
              ],
            ),
            MarkerLayer(markers: _buildMarkers(data, mission, fleet)),
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
          child: _MissionPanel(
            selected: _selected,
            onSelect: (p) => setState(() => _selected = p),
            onSave: () => _saveMission(context),
            onLoad: () => _loadMission(context),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(
      DataStore data, MissionState mission, FleetState fleet) {
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

    // Rescuer last known locations (M7d): one person marker per rescuer.
    for (final loc in data.personnelLocations.items.where((l) => l.hasLocation)) {
      markers.add(Marker(
        point: LatLng(loc.lat!, loc.lon!),
        width: 130,
        height: 44,
        child: Tooltip(
          message: 'rescuer ${loc.personnelId}\n'
              'battery ${loc.batteryPct ?? "?"}%  updated ${loc.updatedAt}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_pin_circle,
                  size: 28, color: Colors.tealAccent),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.black54,
                child: Text(loc.personnelId,
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
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

    // Area polygon vertices (draw mode), so the operator sees each tap.
    if (mission.area.isNotEmpty) {
      for (var i = 0; i < mission.area.length; i++) {
        final v = mission.area[i];
        markers.add(Marker(
          point: LatLng(v.lat, v.lon),
          width: 14,
          height: 14,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.lightBlueAccent,
              border: Border.all(color: Colors.black54),
            ),
          ),
        ));
      }
    }

    // Deployed drones (M7f): moving through their lifecycle. Color by phase.
    for (final d in fleet.deployed) {
      if (d.phase == FleetPhase.landed) continue;
      final color = _fleetPhaseColor(d.phase);
      markers.add(Marker(
        point: LatLng(d.curLat, d.curLon),
        width: 150,
        height: 46,
        child: Tooltip(
          message: '${d.label}: ${d.phase.label}\n${d.note}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(d.phase == FleetPhase.fallback
                  ? Icons.wifi_tethering_off
                  : Icons.flight, size: 28, color: color),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.black54,
                child: Text('${d.label} ${d.phase.label}',
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ));
    }

    // Active deployment placements (role-colored, selectable).
    for (final p in mission.activeDeployment?.placements ??
        const <DronePlacement>[]) {
      final color = _roleColor(p.role);
      final selected = p == _selected;
      markers.add(Marker(
        point: LatLng(p.lat, p.lon),
        width: 140,
        height: 52,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.place,
                size: selected ? 32 : 26, color: color),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              color: selected ? color.withValues(alpha: 0.6) : Colors.black54,
              child: Text('${p.name} (${p.assignedDrone.isEmpty ? p.role : p.assignedDrone})',
                  style: const TextStyle(fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ));
    }

    return markers;
  }

  /// Map tap dispatch: draw an area vertex, move the selected placement,
  /// or drop a new placement, depending on the active mode.
  Future<void> _onMapTap(
      BuildContext context, MissionState mission, LatLng latlng) async {
    if (mission.areaDrawMode) {
      mission.addAreaVertex(latlng.latitude, latlng.longitude);
      return;
    }
    if (!mission.planningMode) return;
    if (_selected != null) {
      mission.movePlacement(_selected!, latlng.latitude, latlng.longitude);
      setState(() => _selected = null);
      return;
    }
    await _addPlacement(context, mission, latlng);
  }

  Future<void> _addPlacement(
      BuildContext context, MissionState mission, LatLng latlng) async {
    final app = context.read<AppState>();
    final active = mission.activeDeployment;
    final count = active?.placements.length ?? 0;
    final nameCtrl = TextEditingController(text: 'position ${count + 1}');
    final radiusCtrl =
        TextEditingController(text: app.coverageRadiusM.toStringAsFixed(0));
    var role = kRoleUserAp;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Placement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${latlng.latitude.toStringAsFixed(5)}, '
                  '${latlng.longitude.toStringAsFixed(5)}'),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(
                      value: kRoleUserAp, child: Text('user AP (victim coverage)')),
                  DropdownMenuItem(
                      value: kRoleMeshRelay, child: Text('mesh relay')),
                  DropdownMenuItem(
                      value: kRoleSystemDrone, child: Text('system drone')),
                ],
                onChanged: (v) => setLocal(() => role = v ?? kRoleUserAp),
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
      ),
    );
    if (confirmed != true) return;
    final radius = double.tryParse(radiusCtrl.text) ?? app.coverageRadiusM;
    mission.addPlacement(DronePlacement(
      name: nameCtrl.text.trim().isEmpty ? 'placement' : nameCtrl.text.trim(),
      lat: latlng.latitude,
      lon: latlng.longitude,
      role: role,
      radiusM: radius,
    ));
    await app.updateSettings(newCoverageRadiusM: radius);
  }

  Future<void> _saveMission(BuildContext context) async {
    final mission = context.read<MissionState>();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save mission',
      fileName:
          '${mission.missionName.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), "_")}.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (path == null) return;
    final err = await mission.saveToFile(path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err ?? 'Mission saved to $path')));
    }
  }

  Future<void> _loadMission(BuildContext context) async {
    final mission = context.read<MissionState>();
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Load mission or legacy plan',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    final err = await mission.loadFromFile(path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? 'Loaded ${mission.missionName}')));
    }
    setState(() => _selected = null);
  }
}

class _MissionPanel extends StatelessWidget {
  final DronePlacement? selected;
  final ValueChanged<DronePlacement?> onSelect;
  final VoidCallback onSave;
  final VoidCallback onLoad;

  const _MissionPanel({
    required this.selected,
    required this.onSelect,
    required this.onSave,
    required this.onLoad,
  });

  @override
  Widget build(BuildContext context) {
    final mission = context.watch<MissionState>();
    final active = mission.activeDeployment;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Planning'),
                  const Spacer(),
                  Switch(
                    value: mission.planningMode,
                    onChanged: (_) => mission.togglePlanning(),
                  ),
                ],
              ),
              if (mission.planningMode) ...[
                Text('Mission: ${mission.missionName}',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: Icon(
                            mission.areaDrawMode
                                ? Icons.check
                                : Icons.pentagon_outlined,
                            size: 16),
                        label: Text(
                            mission.areaDrawMode ? 'Done area' : 'Draw area'),
                        onPressed: () => mission.toggleAreaDraw(),
                      ),
                    ),
                    if (mission.area.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.undo, size: 18),
                        tooltip: 'undo vertex',
                        onPressed: () => mission.undoAreaVertex(),
                      ),
                  ],
                ),
                if (mission.areaDrawMode)
                  Text('tap to add polygon vertices (${mission.area.length})',
                      style: Theme.of(context).textTheme.bodySmall),
                if (!mission.areaDrawMode)
                  Text(
                      selected == null
                          ? 'tap the map to add a placement'
                          : 'tap the map to MOVE "${selected!.name}"',
                      style: Theme.of(context).textTheme.bodySmall),
                const Divider(),
                Text(
                    active == null
                        ? 'no active deployment'
                        : 'deployment: ${active.name}',
                    style: Theme.of(context).textTheme.labelSmall),
                if (active != null && active.placements.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 170),
                    child: ListView(
                      shrinkWrap: true,
                      children: active.placements
                          .map((p) => ListTile(
                                dense: true,
                                selected: p == selected,
                                onTap: () =>
                                    onSelect(p == selected ? null : p),
                                title: Text(p.name,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${p.role}  ${p.radiusM.toStringAsFixed(0)} m'),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18),
                                  onPressed: () {
                                    if (p == selected) onSelect(null);
                                    mission.removePlacement(p);
                                  },
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton(onPressed: onSave, child: const Text('Save')),
                    OutlinedButton(onPressed: onLoad, child: const Text('Load')),
                  ],
                ),
              ],
            ],
          ),
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
            row(Icons.person_pin_circle, Colors.tealAccent, 'rescuer'),
            row(Icons.flag, Colors.purpleAccent, 'field report'),
            row(Icons.airplanemode_active, Colors.cyanAccent, 'node (live)'),
            row(Icons.airplanemode_inactive, Colors.redAccent,
                'node DEGRADED'),
            row(Icons.place, Colors.amber, 'placement: user AP'),
            row(Icons.place, Colors.cyanAccent, 'placement: mesh relay'),
            row(Icons.place, Colors.pinkAccent, 'placement: system drone'),
          ],
        ),
      ),
    );
  }
}
