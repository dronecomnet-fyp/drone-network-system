/// The area map in the victim's app (CHANGES.md item 38): where the drones
/// are, where rescuers are working, and where other people needing help
/// are.
///
/// Why victims see each other at all: in Sri Lankan floods people already
/// post their location publicly to ask for help, and in most disasters
/// neighbours pull people out long before responders arrive. A system that
/// hid survivors from each other would throw that away and push people
/// back to social media, which reaches a larger and far less relevant
/// audience.
///
/// What that decision does NOT extend to: the feed carries positions only,
/// never message content and never device ids (backend/models.py
/// area_map_snapshot). Someone reading this map learns that a person
/// nearby needs help. They cannot read that person's medical details, and
/// they cannot follow one individual across time.
///
/// No tiles, deliberately: there is no internet at a disaster site, so
/// markers sit on a plain background. It is still a real projection, so
/// relative positions and distances are honest.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../constants.dart';
import '../state/app_controller.dart';

class AreaMapScreen extends StatefulWidget {
  const AreaMapScreen({super.key});

  @override
  State<AreaMapScreen> createState() => _AreaMapScreenState();
}

class _AreaMapScreenState extends State<AreaMapScreen> {
  static const Duration _refreshEvery = Duration(seconds: 25);
  static const LatLng _fallback = LatLng(7.8731, 80.7718); // Sri Lanka

  final MapController _map = MapController();
  Timer? _timer;

  List<LatLng> _drones = [];
  List<LatLng> _rescuers = [];
  List<({LatLng at, bool helped})> _victims = [];
  LatLng? _me;
  bool _loading = true;
  String? _error;
  bool _framed = false;

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
    final client = shared.RescueMeshClient(
        baseUrl: kDroneBaseUrl, timeout: const Duration(seconds: 8));
    try {
      final data = await client.getAreaMap();
      if (!mounted) return;
      setState(() {
        _drones = _points(data['drones']);
        _rescuers = _points(data['rescuers']);
        _victims = [
          for (final v in (data['victims'] as List<dynamic>? ?? []))
            if (v is Map && v['lat'] != null && v['lon'] != null)
              (
                at: LatLng((v['lat'] as num).toDouble(),
                    (v['lon'] as num).toDouble()),
                helped: v['helped'] == true,
              ),
        ];
        _me = _myLastPoint();
        _loading = false;
        _error = null;
      });
      _frameOnce();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Not connected to a drone right now.';
      });
    } finally {
      client.close();
    }
  }

  List<LatLng> _points(dynamic list) => [
        for (final p in (list as List<dynamic>? ?? []))
          if (p is Map && p['lat'] != null && p['lon'] != null)
            LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
      ];

  /// The victim's own most recent logged point, so they can see themselves
  /// relative to everything else. Comes from local storage, never the feed.
  LatLng? _myLastPoint() {
    final pts = context.read<AppController>().points;
    if (pts.isEmpty) return null;
    final p = pts.first;
    return LatLng(p.lat, p.lon);
  }

  void _frameOnce() {
    if (_framed) return;
    final all = <LatLng>[..._drones, ..._rescuers, ..._victims.map((v) => v.at)];
    if (_me != null) all.add(_me!);
    if (all.isEmpty) return;
    _framed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fit(all));
  }

  void _fit(List<LatLng> pts) {
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _map.move(pts.first, 15);
      } else {
        _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(56),
          maxZoom: 16,
        ));
      }
    } catch (_) {
      _framed = false; // not laid out yet; try again next refresh
    }
  }

  /// Straight-line distance to the nearest rescuer, which is the single
  /// most reassuring number on this screen.
  String? get _nearestRescuer {
    final me = _me;
    if (me == null || _rescuers.isEmpty) return null;
    const d = Distance();
    var best = double.infinity;
    for (final r in _rescuers) {
      final m = d.as(LengthUnit.Meter, me, r);
      if (m < best) best = m.toDouble();
    }
    if (best.isInfinite) return null;
    return best < 1000
        ? '${best.round()} m away'
        : '${(best / 1000).toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      for (final v in _victims)
        _pin(v.at, v.helped ? Icons.check_circle : Icons.person_pin_circle,
            v.helped ? Colors.green.shade600 : Colors.red.shade600),
      for (final r in _rescuers)
        _pin(r, Icons.health_and_safety, Colors.teal.shade700),
      for (final d in _drones) _pin(d, Icons.flight, Colors.indigo),
      if (_me != null)
        _pin(_me!, Icons.my_location, Colors.blueAccent, size: 26),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Area map'),
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Fit everything',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () => _fit([
              ..._drones,
              ..._rescuers,
              ..._victims.map((v) => v.at),
              ?_me,
            ]),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.amber.shade100,
              padding: const EdgeInsets.all(10),
              child: Text(
                '$_error Showing the last positions received.',
                style: TextStyle(color: Colors.amber.shade900, fontSize: 14),
              ),
            ),
          if (_nearestRescuer != null)
            Container(
              width: double.infinity,
              color: Colors.teal.shade50,
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Icon(Icons.health_and_safety, color: Colors.teal.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Nearest rescue team ${_nearestRescuer!}',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ]),
            ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: const MapOptions(
                      initialCenter: _fallback, initialZoom: 8),
                  children: [MarkerLayer(markers: markers)],
                ),
                if (_loading && markers.isEmpty)
                  const Center(child: CircularProgressIndicator()),
                if (!_loading && markers.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        'Nothing to show yet.\n\nPositions appear here once '
                        'drones and rescue teams are working nearby.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                const Positioned(left: 10, bottom: 10, child: _Legend()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Marker _pin(LatLng at, IconData icon, Color colour, {double size = 22}) =>
      Marker(
        point: at,
        width: 34,
        height: 34,
        child: Icon(icon, color: colour, size: size),
      );
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white.withValues(alpha: 0.93),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(Icons.my_location, Colors.blueAccent, 'You'),
              _row(Icons.flight, Colors.indigo, 'Rescue drone'),
              _row(Icons.health_and_safety, Colors.teal, 'Rescue team'),
              _row(Icons.person_pin_circle, Colors.red, 'Needs help'),
              _row(Icons.check_circle, Colors.green, 'Being helped'),
              const SizedBox(height: 4),
              const SizedBox(
                width: 150,
                child: Text(
                  'No map images offline, so this shows positions only.',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _row(IconData i, Color c, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11)),
        ]),
      );
}
