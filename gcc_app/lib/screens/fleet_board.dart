/// Fleet board (M7f): the deploy/recall control surface, embedded in the
/// Live Ops tab. Manages the WHOLE operation's drones, even though only the
/// system drone is really flown: it shows "Deployed X / Y available" from
/// the mission inventory and disables Deploy when the pool is empty.
///
/// DEMO drones are simulated (auto-return before the battery dies); the
/// system drone, when its MAVLink link is live, is deployed for real over
/// the existing heartbeat-gated command path (PROPS-OFF bench policy
/// unchanged). This widget also forwards the system drone's live telemetry
/// into the fleet battery watchdog.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/data_store.dart';
import '../state/drone_controller.dart';
import '../state/fleet_state.dart';
import '../state/mission_state.dart';

class FleetBoard extends StatefulWidget {
  const FleetBoard({super.key});

  @override
  State<FleetBoard> createState() => _FleetBoardState();
}

class _FleetBoardState extends State<FleetBoard> {
  DroneController? _drone;
  FleetState? _fleet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final drone = context.read<DroneController>();
    final fleet = context.read<FleetState>();
    if (_drone != drone) {
      _drone?.removeListener(_pushTelemetry);
      _drone = drone;
      _fleet = fleet;
      drone.addListener(_pushTelemetry);
    }
  }

  /// Feed the system drone's live telemetry into the fleet watchdog. Cell
  /// count is estimated from pack voltage (~3.7 V nominal/cell) so 3S/4S
  /// both work. Confidence: Low (a configured pack size would be exact).
  void _pushTelemetry() {
    final drone = _drone, fleet = _fleet;
    if (drone == null || fleet == null) return;
    final t = drone.telemetry;
    final realLabels =
        fleet.deployed.where((d) => d.real).map((d) => d.label).toList();
    if (realLabels.isEmpty) return;
    final cells = t.batteryVolts == null
        ? 3
        : (t.batteryVolts! / 3.7).round().clamp(1, 12);
    for (final label in realLabels) {
      fleet.updateReal(
        label,
        lat: t.lat,
        lon: t.lon,
        batteryVolts: drone.linkFresh ? t.batteryVolts : null,
        cellCount: cells,
        armed: t.armed,
      );
    }
  }

  @override
  void dispose() {
    _drone?.removeListener(_pushTelemetry);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fleet = context.watch<FleetState>();
    final mission = context.watch<MissionState>();
    final drone = context.watch<DroneController>();

    final busy = fleet.busyLabels;
    final available =
        mission.drones.where((d) => !busy.contains(d.label)).toList();
    final total = mission.drones.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Fleet', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 10),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                      'Deployed ${fleet.inFlightCount} / ${available.length} available (of $total)'),
                ),
                const Spacer(),
                if (fleet.deployed.any((d) => !d.phase.releasesSlot))
                  TextButton.icon(
                    icon: const Icon(Icons.home, size: 18),
                    label: const Text('Recall all'),
                    onPressed: () => fleet.recallAll(),
                  ),
                FilledButton.icon(
                  icon: const Icon(Icons.flight_takeoff, size: 18),
                  label: const Text('Deploy'),
                  onPressed: available.isEmpty
                      ? null
                      : () => _showDeploy(context, mission, fleet, drone),
                ),
              ],
            ),
            if (available.isEmpty && total > 0)
              Text('No more drones available.',
                  style: Theme.of(context).textTheme.bodySmall),
            if (total == 0)
              Text('Add drones on the Mission tab to deploy.',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            if (fleet.deployed.isEmpty)
              const Text('Nothing deployed.')
            else
              ...fleet.deployed.map((d) => _row(context, fleet, d)),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, FleetState fleet, DeployedDrone d) {
    final reserve = fleet.reservePct(d);
    return ListTile(
      dense: true,
      leading: Icon(
        d.real ? Icons.flight : Icons.airplanemode_active,
        color: _phaseColor(d.phase),
      ),
      title: Row(
        children: [
          Flexible(child: Text(d.label, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Chip(
            visualDensity: VisualDensity.compact,
            backgroundColor: _phaseColor(d.phase).withValues(alpha: 0.25),
            label: Text(d.phase.label, style: const TextStyle(fontSize: 11)),
          ),
          if (d.real) ...[
            const SizedBox(width: 4),
            const Chip(
                visualDensity: VisualDensity.compact,
                label: Text('REAL (bench)', style: TextStyle(fontSize: 10))),
          ] else if (d.pilotAdvisory) ...[
            const SizedBox(width: 4),
            const Chip(
                visualDensity: VisualDensity.compact,
                label:
                    Text('pilot advisory', style: TextStyle(fontSize: 10))),
          ],
        ],
      ),
      subtitle: Text([
        if (!d.real)
          'battery ${d.batteryPct.toStringAsFixed(0)}% (reserve ${reserve.toStringAsFixed(0)}%)',
        'home ${(d.distanceHomeM / 1000).toStringAsFixed(2)} km',
        d.note,
      ].where((s) => s.isNotEmpty).join('  |  ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!d.real && d.phase.isActive)
            IconButton(
              tooltip: 'simulate signal loss (LoRa fallback)',
              icon: const Icon(Icons.sensors_off, size: 18),
              onPressed: () => fleet.simulateSignalLoss(d),
            ),
          if (!d.phase.releasesSlot && d.phase != FleetPhase.lost)
            OutlinedButton(
              onPressed: () => fleet.recall(d),
              child: const Text('Recall'),
            ),
          if (d.phase.releasesSlot || d.phase == FleetPhase.lost)
            IconButton(
              tooltip: 'remove',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => fleet.remove(d),
            ),
        ],
      ),
    );
  }

  Color _phaseColor(FleetPhase p) {
    switch (p) {
      case FleetPhase.onStation:
        return Colors.greenAccent;
      case FleetPhase.enroute:
      case FleetPhase.launchRequested:
        return Colors.amberAccent;
      case FleetPhase.returning:
        return Colors.orangeAccent;
      case FleetPhase.landed:
        return Colors.white54;
      case FleetPhase.fallback:
        return Colors.deepOrange;
      case FleetPhase.lost:
        return Colors.redAccent;
      case FleetPhase.planned:
        return Colors.white70;
    }
  }

  Future<void> _showDeploy(BuildContext context, MissionState mission,
      FleetState fleet, DroneController drone) async {
    final active = mission.activeDeployment;
    if (active == null || active.placements.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'No active deployment with placements. Draw or activate one first.')));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DeployDialog(
        mission: mission,
        fleet: fleet,
        drone: drone,
      ),
    );
  }
}

class _DeployDialog extends StatefulWidget {
  final MissionState mission;
  final FleetState fleet;
  final DroneController drone;

  const _DeployDialog(
      {required this.mission, required this.fleet, required this.drone});

  @override
  State<_DeployDialog> createState() => _DeployDialogState();
}

class _DeployDialogState extends State<_DeployDialog> {
  DronePlacement? _placement;
  DroneResource? _drone;
  bool _real = false;

  @override
  Widget build(BuildContext context) {
    final mission = widget.mission;
    final fleet = widget.fleet;
    final data = context.read<DataStore>();
    final busy = fleet.busyLabels;
    final available =
        mission.drones.where((d) => !busy.contains(d.label)).toList();
    final placements = mission.activeDeployment?.placements ?? [];
    final linkFresh = widget.drone.linkFresh;

    return AlertDialog(
      title: const Text('Deploy a drone'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<DronePlacement>(
              initialValue: _placement,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'To placement'),
              items: placements
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(
                            '${p.name} (${p.role})${p.assignedDrone.isEmpty ? "" : " [${p.assignedDrone}]"}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _placement = v),
            ),
            DropdownButtonFormField<DroneResource>(
              initialValue: _drone,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Drone'),
              items: available
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(
                            '${d.label}${d.source == "brand" ? "" : " (volunteer)"}',
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _drone = v),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('Command over MAVLink (system drone)'),
              subtitle: Text(linkFresh
                  ? 'live link fresh: real deploy, PROPS-OFF bench'
                  : 'no live link: DEMO simulation only'),
              value: _real && linkFresh,
              onChanged:
                  linkFresh ? (v) => setState(() => _real = v) : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: (_placement == null || _drone == null)
              ? null
              : () => _deploy(context, data),
          child: const Text('Deploy'),
        ),
      ],
    );
  }

  void _deploy(BuildContext context, DataStore data) {
    final p = _placement!;
    final d = _drone!;
    final mission = widget.mission;
    final specs = mission.specsFor(d);

    // Home = the connected node's GPS if it has a fix, else the operation
    // area centroid, else a point offset from the target so the demo leg is
    // visible.
    final (homeLat, homeLon) = _home(data, mission, p);

    p.assignedDrone = d.label;
    mission.touch();

    widget.fleet.deploy(
      label: d.label,
      source: d.source,
      real: _real && widget.drone.linkFresh,
      homeLat: homeLat,
      homeLon: homeLon,
      targetLat: p.lat,
      targetLon: p.lon,
      role: p.role,
      radiusM: p.radiusM,
      batteryWh: specs?.batteryWh,
    );
    Navigator.pop(context);
  }

  (double, double) _home(
      DataStore data, MissionState mission, DronePlacement p) {
    final gps = data.health?.gps;
    if (gps != null && gps.hasFix) return (gps.lat!, gps.lon!);
    if (mission.area.length >= 3) {
      final lat =
          mission.area.map((v) => v.lat).reduce((a, b) => a + b) /
              mission.area.length;
      final lon =
          mission.area.map((v) => v.lon).reduce((a, b) => a + b) /
              mission.area.length;
      return (lat, lon);
    }
    // ~550 m south of the target.
    return (p.lat - 0.005, p.lon);
  }
}
