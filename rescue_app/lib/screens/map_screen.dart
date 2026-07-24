/// Ops Map (task D): the GCC operations map, brought to the rescuer's
/// phone so a field team can see victims, their teammates, and drones on
/// one picture instead of scrolling three list screens.
///
/// OFFLINE by design: there is no internet at a deployment and this app
/// ships no MBTiles file, so markers render on flutter_map's plain
/// background (a "markers on a plain grid" view, the user's choice). It is
/// still a real geographic projection: pan and zoom work, positions are
/// true lat/lon, only the tile imagery is absent.
///
/// Layers:
///   victims  - victim messages (red NEW / green CLAIMED) and emergency
///              checkins (blue, orange when SOS)
///   team     - other rescuers' last reported location (teal, named); the
///              logged-in rescuer's own position is a blue dot
///   drones   - the connected node's GPS (indigo), and DEGRADED nodes at
///              their last LoRa-beaconed position (red)
///
/// Data is polled only while this tab is on screen: the rescue app builds
/// just the selected screen, so the poll timer starts in initState and is
/// cancelled in dispose (battery-friendly, like the heartbeat).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../models/message_model.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const Duration _refreshEvery = Duration(seconds: 12);

  // Sri Lanka centroid, the same no-data fallback the GCC map uses.
  static const LatLng _fallbackCenter = LatLng(7.8731, 80.7718);

  final MapController _map = MapController();

  Timer? _timer;
  bool _loading = true;
  bool _centeredOnData = false;
  String? _error;

  List<Message> _victims = [];
  List<shared.Checkin> _checkins = [];
  List<shared.PersonnelLocation> _people = [];
  shared.NodeHealth? _health;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(_refreshEvery, (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final results = await Future.wait([
        APIService.getMessages(),
        APIService.getCheckins(),
        APIService.getPersonnelLocations(),
        APIService.getHealth(),
      ]);
      if (!mounted) {
        return;
      }
      setState(() {
        _victims = results[0] as List<Message>;
        _checkins = results[1] as List<shared.Checkin>;
        _people = results[2] as List<shared.PersonnelLocation>;
        _health = results[3] as shared.NodeHealth;
        _updatedAt = DateTime.now();
        _loading = false;
        _error = null;
      });
      _centerOnDataOnce();
    } catch (e) {
      if (!mounted) {
        return;
      }
      // Keep the last good picture; just surface that the refresh failed.
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// All points worth showing, used for the first auto-centre and for the
  /// "fit to markers" button.
  List<LatLng> _allPoints() {
    final points = <LatLng>[];
    for (final m in _victims) {
      if (m.hasGpsLocation) {
        points.add(LatLng(m.userLat!, m.userLon!));
      }
    }
    for (final c in _checkins) {
      if (c.lat != null && c.lon != null) {
        points.add(LatLng(c.lat!, c.lon!));
      }
    }
    for (final p in _people) {
      if (p.hasLocation) {
        points.add(LatLng(p.lat!, p.lon!));
      }
    }
    final gps = _health?.gps;
    if (gps != null && gps.hasFix) {
      points.add(LatLng(gps.lat!, gps.lon!));
    }
    for (final d in _health?.degradedNodes ?? const <shared.DegradedNode>[]) {
      if (d.lat != null && d.lon != null) {
        points.add(LatLng(d.lat!, d.lon!));
      }
    }
    return points;
  }

  void _centerOnDataOnce() {
    if (_centeredOnData) {
      return;
    }
    // Only latch "centered" once the move actually lands: the first refresh
    // is fired from initState, so data can arrive before the FlutterMap is
    // laid out and the controller is ready.
    if (_fit(_allPoints())) {
      _centeredOnData = true;
    }
  }

  bool _fit(List<LatLng> points) {
    if (points.isEmpty) {
      return false;
    }
    try {
      if (points.length == 1) {
        _map.move(points.first, 15);
      } else {
        _map.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(points),
            padding: const EdgeInsets.all(48),
            maxZoom: 16,
          ),
        );
      }
      return true;
    } catch (_) {
      // Map not attached yet; a later refresh (or the button) will retry.
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selfId = context.watch<AuthProvider>().personnelId;
    final markers = _buildMarkers(selfId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ops Map'),
        backgroundColor: Colors.indigo.shade700,
        elevation: 4,
        actions: [
          IconButton(
            tooltip: 'Fit to markers',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => _fit(_allPoints()),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: const MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 8,
            ),
            children: [
              MarkerLayer(markers: markers),
            ],
          ),
          if (_loading && markers.isEmpty)
            const Center(child: CircularProgressIndicator()),
          if (!_loading && markers.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No mapped victims, teammates, or drones yet.\n'
                  'Positions appear here as they are reported.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: _LegendCard(updatedAt: _updatedAt, error: _error),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers(String selfId) {
    final markers = <Marker>[];

    // Victims: messages first, then emergency checkins.
    for (final m in _victims) {
      if (!m.hasGpsLocation) {
        continue;
      }
      final claimed = m.isClaimed;
      markers.add(_marker(
        LatLng(m.userLat!, m.userLon!),
        Icons.person_pin_circle,
        claimed ? Colors.green.shade700 : Colors.red.shade700,
      ));
    }
    for (final c in _checkins) {
      if (c.lat == null || c.lon == null) {
        continue;
      }
      markers.add(_marker(
        LatLng(c.lat!, c.lon!),
        c.sos ? Icons.sos : Icons.circle,
        c.sos ? Colors.orange.shade800 : Colors.blue.shade600,
        size: c.sos ? 30 : 16,
      ));
    }

    // Team: self as a blue dot, other rescuers named in teal.
    for (final p in _people) {
      if (!p.hasLocation) {
        continue;
      }
      final isSelf = p.personnelId == selfId;
      markers.add(_marker(
        LatLng(p.lat!, p.lon!),
        isSelf ? Icons.my_location : Icons.person_pin,
        isSelf ? Colors.blueAccent : Colors.teal.shade600,
        label: isSelf ? 'me' : p.personnelId,
      ));
    }

    // Drones: connected node GPS, then degraded nodes on LoRa fallback.
    final gps = _health?.gps;
    if (gps != null && gps.hasFix) {
      markers.add(_marker(
        LatLng(gps.lat!, gps.lon!),
        Icons.flight,
        Colors.indigo,
        label: _health?.nodeId,
      ));
    }
    for (final d in _health?.degradedNodes ?? const <shared.DegradedNode>[]) {
      if (d.lat == null || d.lon == null) {
        continue;
      }
      markers.add(_marker(
        LatLng(d.lat!, d.lon!),
        Icons.flight,
        Colors.red.shade700,
        label: '${d.nodeId} (LoRa)',
      ));
    }

    return markers;
  }

  Marker _marker(
    LatLng point,
    IconData icon,
    Color color, {
    double size = 30,
    String? label,
  }) =>
      Marker(
        point: point,
        width: 96,
        height: 58,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: size),
            if (label != null && label.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({this.updatedAt, this.error});

  final DateTime? updatedAt;
  final String? error;

  String get _age {
    if (updatedAt == null) {
      return 'never';
    }
    final s = DateTime.now().difference(updatedAt!).inSeconds;
    if (s < 60) {
      return '${s}s ago';
    }
    return '${s ~/ 60}m ago';
  }

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white.withValues(alpha: 0.92),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _row(Icons.person_pin_circle, Colors.red.shade700,
                  'victim (new)'),
              _row(Icons.person_pin_circle, Colors.green.shade700,
                  'victim (claimed)'),
              _row(Icons.sos, Colors.orange.shade800, 'SOS checkin'),
              _row(Icons.person_pin, Colors.teal.shade600, 'rescuer'),
              _row(Icons.my_location, Colors.blueAccent, 'me'),
              _row(Icons.flight, Colors.indigo, 'drone (live)'),
              _row(Icons.flight, Colors.red.shade700, 'drone (LoRa fallback)'),
              const Divider(height: 12),
              Text(
                error == null ? 'updated $_age' : 'stale ($_age): offline?',
                style: TextStyle(
                  fontSize: 11,
                  color: error == null ? Colors.black54 : Colors.red.shade700,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _row(IconData icon, Color color, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );
}
