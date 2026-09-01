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

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:latlong2/latlong.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

import '../main.dart' show ShellNav;
import '../services/mission_validator.dart';
import '../state/app_state.dart';
import '../state/data_store.dart';
import '../state/drone_controller.dart';
import '../state/fleet_state.dart';
import '../state/mission_state.dart';
import '../widgets/blinking.dart';
import '../widgets/degraded_alert.dart';
import '../widgets/map_filters.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  /// The map had no controller at all, which is why nothing could ever
  /// re-centre it: the camera was set once from initialCenter and then
  /// frozen. Drawing an operation area left the operator looking at
  /// whatever the map happened to open on (CHANGES.md item 35).
  final MapController _map = MapController();

  /// Area polygon we have already auto-focused, so we do it when the area
  /// first appears or changes, and never fight the operator afterwards
  /// while they are panning around.
  int _focusedAreaHash = 0;

  MbTiles? _mbtiles;
  String _openedPath = '';
  String? _tileError;

  // When a placement is selected in the panel, the next map tap MOVES it
  // (flutter_map has no native marker drag).
  DronePlacement? _selected;

  // Sri Lanka centroid as the no-data fallback view.
  static const _fallbackCenter = LatLng(7.8731, 80.7718);

  /// Which layers are drawn (field backlog #13). Everything on by default:
  /// an operator who has not touched the filters must see the whole
  /// picture, and hiding something they never asked to hide is how a
  /// victim gets missed.
  final MapFilters _filters = MapFilters();

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

  /// Frame the operation area once it exists, and again if it is redrawn.
  /// Deferred to after the frame because the camera cannot be moved while
  /// the map is still being laid out.
  void _autoFocusArea(MissionState mission) {
    if (mission.area.length < 3) return;
    final hash = Object.hashAll(
        mission.area.map((p) => '${p.lat},${p.lon}'));
    if (hash == _focusedAreaHash) return;
    _focusedAreaHash = hash;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focusArea(mission);
    });
  }

  /// Fit the camera to the operation area. Also wired to a button, because
  /// an operator who has panned away wants one obvious way back.
  void focusArea(MissionState mission) {
    if (mission.area.length < 3) return;
    final pts = mission.area.map((p) => LatLng(p.lat, p.lon)).toList();
    try {
      _map.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pts),
        padding: const EdgeInsets.all(64),
        maxZoom: 16,
      ));
    } catch (_) {
      // Map not attached yet; the next area change or button press retries.
    }
  }

  /// Deepest zoom the loaded MBTiles actually contains. Without a file
  /// there are no tiles at all, so any limit is arbitrary and 19 simply
  /// keeps marker work sane.
  double get _maxNativeZoom {
    final z = _mbtiles?.getMetadata().maxZoom;
    return z == null ? 19 : z.toDouble();
  }

  /// How far the camera may go. A little past the native maximum, so the
  /// operator can zoom in for detail on markers and get upscaled tiles
  /// rather than an empty screen.
  double get _maxUsefulZoom => _maxNativeZoom + 2;

  /// Rotation for an arrow head, in radians clockwise from north, which is
  /// what Transform.rotate wants for an icon that points up by default.
  /// Equirectangular is fine at the scale of one operation area and avoids
  /// a spherical formula nobody will check.
  double _bearingRad(GeoPoint from, GeoPoint to) {
    final dx = (to.lon - from.lon) *
        math.cos((from.lat + to.lat) / 2 * math.pi / 180);
    final dy = to.lat - from.lat;
    return math.atan2(dx, dy);
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
    final drone = context.watch<DroneController>();
    final nav = context.watch<ShellNav>();
    _syncTiles(app.mbtilesPath);

    final targetCoord = nav.takeTargetMapCoord();
    if (targetCoord != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          _map.move(LatLng(targetCoord.$1, targetCoord.$2), 15);
        } catch (_) {}
      });
    }

    final active = mission.activeDeployment;
    // Field backlog #3c: an UNAPPROVED plan is a proposal, and a proposal
    // sitting on the operations map is indistinguishable from a decision.
    // Drafts are visible while planning and nowhere else, so what the map
    // shows outside planning mode is only what somebody signed off.
    final showActive =
        active != null && (active.approved || mission.planningMode);
    _autoFocusArea(mission);

    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: _initialCenter(data),
            initialZoom: 13,
            // Field backlog #5: zooming in far left the screen blank.
            // An MBTiles file only contains tiles up to a certain zoom, and
            // past that flutter_map has nothing to draw. Clamping the
            // camera to what the file actually holds means the operator
            // cannot zoom into an empty void in the first place, and
            // maxNativeZoom on the layer upscales the deepest real tiles
            // rather than showing nothing.
            maxZoom: _maxUsefulZoom,
            minZoom: 2,
            onTap: (tapPosition, latlng) => _onMapTap(context, mission, latlng),
          ),
          children: [
            if (_mbtiles != null)
              TileLayer(
                tileProvider: MbTilesTileProvider(
                    mbtiles: _mbtiles!, silenceTileNotFound: true),
                // Beyond this the deepest available tiles are scaled up,
                // which is blurry but readable, instead of blank.
                maxNativeZoom: _maxNativeZoom.round(),
                maxZoom: _maxUsefulZoom,
              ),
            // The area is SHADED only while planning (field backlog #3).
            // Once the mission is running, a permanent wash of colour over
            // the whole operation makes every marker under it harder to
            // read, and the operator already knows where the area is. The
            // outline stays, thin, so the boundary is still available.
            if (mission.area.length >= 3)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: mission.area
                        .map((p) => LatLng(p.lat, p.lon))
                        .toList(),
                    color: mission.planningMode
                        ? Colors.lightBlue.withValues(alpha: 0.10)
                        : Colors.transparent,
                    borderColor: mission.planningMode
                        ? Colors.lightBlueAccent
                        : Colors.lightBlueAccent.withValues(alpha: 0.45),
                    borderStrokeWidth: mission.planningMode ? 2 : 1,
                  ),
                ],
              ),
            // Suspected areas (field backlog #4). Drawn under the
            // placements so an operator's hunch never hides the thing the
            // plan actually commits to.
            CircleLayer(
              circles: [
                for (final sa in _filters.intent
                    ? mission.suspectedAreas
                    : const <SuspectedArea>[])
                  CircleMarker(
                    point: LatLng(sa.center.lat, sa.center.lon),
                    radius: sa.radiusM,
                    useRadiusInMeter: true,
                    color: Colors.amber.withValues(alpha: 0.10),
                    borderColor: Colors.amberAccent,
                    borderStrokeWidth: 1.5,
                  ),
              ],
            ),
            if (_filters.intent && mission.arrows.isNotEmpty)
              PolylineLayer(
                polylines: [
                  for (final a in mission.arrows)
                    Polyline(
                      points: [
                        LatLng(a.from.lat, a.from.lon),
                        LatLng(a.to.lat, a.to.lon),
                      ],
                      color: Colors.amberAccent,
                      strokeWidth: 3,
                    ),
                ],
              ),
            CircleLayer(
              circles: [
                for (final p in _filters.placements && showActive
                    ? active.placements
                    : const <DronePlacement>[])
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
            MarkerLayer(markers: _buildMarkers(data, mission, fleet, drone)),
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
        // Fallback alert (task C): a drone on LoRa fallback (Pi down) is an
        // emergency, so it sits as a red banner over the map, below the
        // no-map notice if that is showing.
        Positioned(
          top: _mbtiles == null ? 84 : 12,
          left: 12,
          width: 320,
          child: const DegradedAlert(),
        ),
        Positioned(
          bottom: 12,
          left: 12,
          child: _LegendCard(),
        ),
        Positioned(
          bottom: 12,
          right: 12,
          child: MapFilterButton(
            filters: _filters,
            onChanged: () => setState(() {}),
            counts: {
              'victims':
                  data.messages.items.where((m) => m.hasUserLocation).length,
              'checkins': data.checkins.items.length,
              'reports':
                  data.gsMessages.items.where((g) => g.hasLocation).length,
              'rescuers': data.personnelLocations.items
                  .where((l) => l.hasLocation)
                  .length,
              'placements': active?.placements.length ?? 0,
              'fleet': fleet.deployed.length,
              'degraded': data.health?.degradedNodes.length ?? 0,
            },
          ),
        ),
        Positioned(
          top: _mbtiles == null ? 84 : 12,
          right: 12,
          child: _MissionPanel(
            selected: _selected,
            onSelect: (p) => setState(() => _selected = p),
            onSave: () => _saveMission(context),
            onSaveAs: () => _saveMission(context, saveAs: true),
            onLoad: () => _loadMission(context),
            onFocusArea: () => focusArea(mission),
          ),
        ),
      ],
    );
  }

  List<Marker> _buildMarkers(
      DataStore data, MissionState mission, FleetState fleet,
      DroneController drone) {
    final markers = <Marker>[];

    // System drone live MAVLink position (M7 / task B). This is the drone's
    // OWN GPS over the live control link, shown whenever the GCC is connected
    // to it, independent of which node's /health we are polling and of any
    // fleet deployment. That is why it shows over the relay path, where the
    // dashboard is polling a volunteer node's /health and would otherwise
    // never see DRONE_S's position or battery.
    final dt = drone.telemetry;
    if (_filters.nodes && drone.connected && dt.lat != null && dt.lon != null) {
      final fresh = drone.linkFresh;
      final bat = dt.batteryVolts == null
          ? 'battery n/a'
          : '${dt.batteryVolts!.toStringAsFixed(2)} V'
              '${dt.batteryRemaining != null && dt.batteryRemaining! >= 0 ? " ${dt.batteryRemaining}%" : ""}';
      markers.add(Marker(
        point: LatLng(dt.lat!, dt.lon!),
        width: 150,
        height: 48,
        child: Tooltip(
          message: 'System drone (live MAVLink)\n'
              '${dt.armed ? "ARMED" : "disarmed"}  ${dt.modeName}\n'
              '$bat  ${dt.hasGpsFix ? "${dt.satellites} sats" : "no fix"}'
              '${fresh ? "" : "\nlink STALE"}',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.flight,
                  size: 30,
                  color: fresh ? Colors.pinkAccent : Colors.grey),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.black54,
                child: Text('system drone $bat',
                    style: const TextStyle(fontSize: 10),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      ));
    }

    // Victim messages with a user location.
    for (final m in _filters.victims
        ? data.messages.items.where((m) => m.hasUserLocation)
        : const <Message>[]) {
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
    for (final c in _filters.checkins ? data.checkins.items : const <Checkin>[]) {
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
    for (final loc in _filters.rescuers
        ? data.personnelLocations.items.where((l) => l.hasLocation)
        : const <PersonnelLocation>[]) {
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
    for (final g in _filters.reports
        ? data.gsMessages.items.where((g) => g.hasLocation)
        : const <GsMessage>[]) {
      markers.add(Marker(
        point: LatLng(g.locationLat!, g.locationLon!),
        width: 30,
        height: 30,
        child: GestureDetector(
          onTap: () => _showFieldReportDetails(context, g),
          child: Tooltip(
            message: 'Report by ${g.sender}: "${g.content}" (tap to inspect)',
            child: Container(
              decoration: BoxDecoration(
                color: Colors.purple.shade900.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.purpleAccent, width: 1.5),
              ),
              child: const Icon(Icons.flag, size: 18, color: Colors.white),
            ),
          ),
        ),
      ));
    }

    // Connected node at its GPS position.
    final gps = data.health?.gps;
    if (_filters.nodes && gps != null && gps.hasFix) {
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

    // Degraded nodes at their last beaconed position. Blinking, because a
    // static red icon on a map this busy does not get noticed (field
    // backlog #13). It stops on its own when the node stops being
    // reported as degraded.
    if (_filters.degraded) {
      for (final d in data.health?.degradedNodes ?? const []) {
        if (d.lat == null || d.lon == null) continue;
        markers.add(Marker(
          point: LatLng(d.lat!, d.lon!),
          width: 44,
          height: 44,
          child: Tooltip(
            message: '${d.nodeId} DEGRADED (last beacon ${d.ts})',
            child: const Blinking(
              child: Icon(Icons.airplanemode_inactive,
                  size: 40, color: Colors.redAccent),
            ),
          ),
        ));
      }
    }

    // The GCC itself (field backlog #4). Nothing in the system can know
    // where this is: it is a laptop in a tent with no GPS, so the
    // operator places it, and everything downstream that reasons about
    // distance from HQ depends on it being here.
    final gcc = mission.gccPosition;
    if (_filters.intent && gcc != null) {
      markers.add(Marker(
        point: LatLng(gcc.lat, gcc.lon),
        width: 120,
        height: 46,
        child: Tooltip(
          message: 'Ground control centre (placed by the operator)',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.home_work, size: 28, color: Colors.orangeAccent),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                color: Colors.black54,
                child: const Text('GCC', style: TextStyle(fontSize: 10)),
              ),
            ],
          ),
        ),
      ));
    }

    if (_filters.intent) {
      // Arrow heads. flutter_map draws lines, not arrows, so the head is a
      // marker at the far end: cheaper and clearer than rotating a custom
      // painter, and it stays the same size at every zoom.
      for (final a in mission.arrows) {
        markers.add(Marker(
          point: LatLng(a.to.lat, a.to.lon),
          width: 150,
          height: 44,
          child: Tooltip(
            message: a.note.isEmpty ? 'expected advance' : a.note,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.rotate(
                  angle: _bearingRad(a.from, a.to),
                  child: const Icon(Icons.navigation,
                      size: 26, color: Colors.amberAccent),
                ),
                if (a.note.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    color: Colors.black54,
                    child: Text(a.note,
                        style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ));
      }

      // The tail of an arrow the operator has started but not finished, so
      // a half-drawn arrow is visible rather than invisible state.
      final start = mission.arrowStart;
      if (start != null) {
        markers.add(Marker(
          point: LatLng(start.lat, start.lon),
          width: 20,
          height: 20,
          child: const Icon(Icons.adjust, size: 20, color: Colors.amberAccent),
        ));
      }

      for (final sa in mission.suspectedAreas) {
        markers.add(Marker(
          point: LatLng(sa.center.lat, sa.center.lon),
          width: 160,
          height: 40,
          child: Tooltip(
            message: sa.note.isEmpty
                ? 'suspected area, ${sa.radiusM.toStringAsFixed(0)} m'
                : '${sa.note} (${sa.radiusM.toStringAsFixed(0)} m)',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.help_outline,
                    size: 20, color: Colors.amberAccent),
                if (sa.note.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    color: Colors.black54,
                    child: Text(sa.note,
                        style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          ),
        ));
      }
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
    for (final d in _filters.fleet ? fleet.deployed : const <DeployedDrone>[]) {
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

    // Active deployment placements (role-colored, selectable). Drafts show
    // only while planning (field backlog #3c) and BLINK until approved, so
    // a proposal never reads as a decision.
    final activeDep = mission.activeDeployment;
    final draft = activeDep != null && !activeDep.approved;
    for (final p in _filters.placements &&
            activeDep != null &&
            (activeDep.approved || mission.planningMode)
        ? activeDep.placements
        : const <DronePlacement>[]) {
      final color = _roleColor(p.role);
      final selected = p == _selected;
      final pin = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place, size: selected ? 32 : 26, color: color),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            color: selected ? color.withValues(alpha: 0.6) : Colors.black54,
            child: Text(
                '${p.name} (${p.assignedDrone.isEmpty ? p.role : p.assignedDrone})',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      );
      markers.add(Marker(
        point: LatLng(p.lat, p.lon),
        width: 140,
        height: 52,
        // Blinking says "not decided yet" without a legend to read
        // (field backlog #3b). It stops the moment the deployment is
        // approved, because the widget is simply no longer wrapped.
        child: draft ? Blinking(minOpacity: 0.45, child: pin) : pin,
      ));
    }

    return markers;
  }

  /// Map tap dispatch: draw an area vertex, move the selected placement,
  /// or drop a new placement, depending on the active mode.
  Future<void> _onMapTap(
      BuildContext context, MissionState mission, LatLng latlng) async {
    // One mode at a time (field backlog #4). A map where a tap could mean
    // four different things is a map the operator cannot use.
    switch (mission.drawMode) {
      case MapDrawMode.area:
        mission.addAreaVertex(latlng.latitude, latlng.longitude);
        return;
      case MapDrawMode.gcc:
        mission.setGccPosition(latlng.latitude, latlng.longitude);
        // Single tap, then straight back out: placing the GCC twice by
        // accident is far more likely than wanting to place it twice.
        mission.setDrawMode(MapDrawMode.none);
        return;
      case MapDrawMode.arrow:
        final completed =
            mission.addArrowPoint(latlng.latitude, latlng.longitude);
        if (completed) await _annotateArrow(context, mission);
        return;
      case MapDrawMode.suspected:
        await _addSuspectedArea(context, mission, latlng);
        return;
      case MapDrawMode.none:
        break;
    }
    if (!mission.planningMode) return;
    if (_selected != null) {
      mission.movePlacement(_selected!, latlng.latitude, latlng.longitude);
      setState(() => _selected = null);
      return;
    }
    await _addPlacement(context, mission, latlng);
  }

  /// Asked once the second tap lands, because an arrow with no reason
  /// attached is close to useless to the AI and to whoever reads the plan
  /// tomorrow. Skippable: an operator mid-briefing should not be blocked
  /// by a text box.
  Future<void> _annotateArrow(
      BuildContext context, MissionState mission) async {
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Direction of advance'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Why do you expect the operation to move this way? The AI '
                'advisor cannot infer intent from the map, so this is the '
                'part only you can supply.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  hintText: 'e.g. pushing north as the water drops',
                ),
                onSubmitted: (v) => Navigator.of(ctx).pop(v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('Skip')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(ctrl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (note != null && note.trim().isNotEmpty) {
      mission.annotateLastArrow(note);
    }
  }

  Future<void> _addSuspectedArea(
      BuildContext context, MissionState mission, LatLng latlng) async {
    final radiusCtrl = TextEditingController(text: '200');
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suspected area'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${latlng.latitude.toStringAsFixed(5)}, '
                  '${latlng.longitude.toStringAsFixed(5)}'),
              const SizedBox(height: 4),
              const Text(
                'A place you suspect needs attention. This carries no '
                'authority on its own: it tells the advisor where to bias '
                'coverage, and tells the next shift what you were thinking.',
                style: TextStyle(fontSize: 12),
              ),
              TextField(
                controller: radiusCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Radius (m)'),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'What do you suspect?',
                  hintText: 'e.g. school, reported by a caller',
                ),
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
              child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    final r = double.tryParse(radiusCtrl.text.trim()) ?? 200;
    mission.addSuspectedArea(
        latlng.latitude, latlng.longitude, r.clamp(10, 20000),
        note: noteCtrl.text.trim());
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
    final check = MissionValidator.checkPlacementLocation(
      lat: latlng.latitude,
      lon: latlng.longitude,
      mission: mission,
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.place, size: 20, color: Colors.amber),
              SizedBox(width: 8),
              Text('New Placement'),
            ],
          ),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${latlng.latitude.toStringAsFixed(5)}, ${latlng.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontSize: 12, color: Colors.white54),
                ),
                if (check.warnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.amberAccent, width: 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: check.warnings
                          .map((w) => Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber,
                                      color: Colors.amberAccent, size: 14),
                                  const SizedBox(width: 4),
                                  Expanded(
                                      child: Text(w,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Colors.white))),
                                ],
                              ))
                          .toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: const [
                    DropdownMenuItem(
                        value: kRoleUserAp,
                        child: Text('user AP (victim coverage)')),
                    DropdownMenuItem(
                        value: kRoleMeshRelay, child: Text('mesh relay')),
                    DropdownMenuItem(
                        value: kRoleSystemDrone, child: Text('system drone')),
                  ],
                  onChanged: (v) => setLocal(() => role = v ?? kRoleUserAp),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: radiusCtrl,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Coverage radius (m)'),
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
                child: const Text('Add Placement')),
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

  void _showFieldReportDetails(BuildContext context, GsMessage g) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.flag, color: Colors.purpleAccent, size: 22),
            SizedBox(width: 8),
            Text('Field Report'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                g.content,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.person, size: 14),
                    label: Text(g.sender.isEmpty ? 'unknown' : g.sender),
                  ),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: const Icon(Icons.access_time, size: 14),
                    label: Text(g.timestamp),
                  ),
                  if (g.nodeId.isNotEmpty)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.hub, size: 14),
                      label: Text('via ${g.nodeId}'),
                    ),
                  if (g.hasLocation)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      avatar: const Icon(Icons.place, size: 14, color: Colors.cyanAccent),
                      label: Text(
                        '${g.locationLat!.toStringAsFixed(5)}, ${g.locationLon!.toStringAsFixed(5)}',
                        style: const TextStyle(color: Colors.cyanAccent),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.inbox, size: 16),
            label: const Text('Open in Live Feed'),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ShellNav>().goToLiveFeed(source: 'REPORTS');
            },
          ),
        ],
      ),
    );
  }

  /// Save over the file this mission came from, asking only the first time
  /// (field backlog #15). Save used to call the file picker every time, so
  /// every save produced ANOTHER file and the operator ended up with a
  /// folder of near-identical missions and no idea which was current.
  Future<void> _saveMission(BuildContext context, {bool saveAs = false}) async {
    final mission = context.read<MissionState>();
    var path = mission.filePath;

    if (saveAs || path == null || path.isEmpty) {
      path = await FilePicker.platform.saveFile(
        dialogTitle: saveAs ? 'Save mission as' : 'Save mission',
        fileName:
            '${mission.missionName.replaceAll(RegExp(r"[^A-Za-z0-9_-]"), "_")}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null) return;
    }

    final err = await mission.saveToFile(path);
    if (err == null) mission.rememberFilePath(path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? 'Saved to ${path.split(Platform.pathSeparator).last}')));
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
    // Loading sets the save target too, so the next Save writes back to the
    // file the operator opened rather than asking where to put it.
    if (err == null) mission.rememberFilePath(path);
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
  final VoidCallback onSaveAs;
  final VoidCallback onLoad;
  final VoidCallback onFocusArea;

  const _MissionPanel({
    required this.selected,
    required this.onSelect,
    required this.onSave,
    required this.onSaveAs,
    required this.onLoad,
    required this.onFocusArea,
  });

  /// One line telling the operator what their next tap will do. The map
  /// has five possible meanings for a tap now, and a mode you cannot see
  /// is a mode you will use by accident.
  String _drawHint(MissionState mission, DronePlacement? selected) {
    switch (mission.drawMode) {
      case MapDrawMode.area:
        return 'tap to add polygon vertices (${mission.area.length})';
      case MapDrawMode.gcc:
        return 'tap where the ground control centre is';
      case MapDrawMode.arrow:
        return mission.arrowStart == null
            ? 'tap where the advance STARTS'
            : 'now tap where it is heading';
      case MapDrawMode.suspected:
        return 'tap the centre of an area you suspect';
      case MapDrawMode.none:
        return selected == null
            ? 'tap the map to add a placement'
            : 'tap the map to MOVE "${selected.name}"';
    }
  }

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
                    if (mission.area.length >= 3)
                      IconButton(
                        icon: const Icon(Icons.center_focus_strong, size: 18),
                        tooltip: 'focus the operation area',
                        onPressed: onFocusArea,
                      ),
                  ],
                ),
                // Field backlog #4: the operator places the GCC, draws
                // where they expect to advance, and circles what they
                // suspect. None of it can be inferred from a map, and all
                // of it is fed to the advisor.
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.home_work, size: 16),
                        label: Text(mission.gccPosition == null
                            ? 'Place GCC'
                            : 'Move GCC'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              mission.drawMode == MapDrawMode.gcc
                                  ? Colors.orangeAccent
                                  : null,
                        ),
                        onPressed: () =>
                            mission.toggleDrawMode(MapDrawMode.gcc),
                      ),
                    ),
                    if (mission.gccPosition != null)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'remove the GCC marker',
                        onPressed: () => mission.clearGccPosition(),
                      ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.trending_up, size: 16),
                        label: Text('Advance (${mission.arrows.length})'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              mission.drawMode == MapDrawMode.arrow
                                  ? Colors.amberAccent
                                  : null,
                        ),
                        onPressed: () =>
                            mission.toggleDrawMode(MapDrawMode.arrow),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.help_outline, size: 16),
                        label:
                            Text('Suspect (${mission.suspectedAreas.length})'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              mission.drawMode == MapDrawMode.suspected
                                  ? Colors.amberAccent
                                  : null,
                        ),
                        onPressed: () =>
                            mission.toggleDrawMode(MapDrawMode.suspected),
                      ),
                    ),
                  ],
                ),
                Text(_drawHint(mission, selected),
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
                    OutlinedButton(
                      onPressed: onSave,
                      // Shows WHERE it will go, so "Save" never silently
                      // overwrites a file the operator forgot they opened.
                      child: Text(context.watch<MissionState>().filePath == null
                          ? 'Save...'
                          : 'Save'),
                    ),
                    OutlinedButton(
                        onPressed: onSaveAs, child: const Text('Save as...')),
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
            row(Icons.flight, Colors.pinkAccent, 'system drone (live)'),
            row(Icons.place, Colors.amber, 'placement: user AP'),
            row(Icons.place, Colors.cyanAccent, 'placement: mesh relay'),
            row(Icons.place, Colors.pinkAccent, 'placement: system drone'),
          ],
        ),
      ),
    );
  }
}
