import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/mission_state.dart';

void main() {
  test('mission JSON round trip preserves identity, area, resources, plans',
      () {
    final m = MissionState();
    m.setMissionInfo(name: 'Flood 2026', type: 'flood');
    m.addChallenge('night ops');
    m.addChallenge('washed-out roads');
    m.addAreaVertex(6.90, 79.85);
    m.addAreaVertex(6.95, 79.85);
    m.addAreaVertex(6.95, 79.90);
    m.setCounts(personnel: 12, batteries: 6);
    m.addModule(ModuleResource(unitId: 'DCM-A-0042', label: 'module A'));
    m.addDrone(DroneResource(label: 'relay-1', unitId: 'DRN-S-0007'));
    m.addDrone(DroneResource(
      label: "Ann's drone",
      source: 'volunteer',
      makeModel: 'DJI Mavic',
      owner: 'Ann',
      attachedModuleId: 'DCM-A-0042',
    ));
    m.cacheProduct(
        'DRN-S-0007',
        const ProductInfo(
          modelNo: 'AS5',
          name: 'AeroSync 5',
          specs: {'ap_range_m': 400, 'mesh_range_m': 1200},
          fetchedAt: '2026-07-21T00:00:00Z',
        ));
    m.addDeployment(Deployment(name: 'plan A', source: 'ai', placements: [
      DronePlacement(
          name: 'relay N', lat: 6.92, lon: 79.86, role: kRoleMeshRelay, radiusM: 500),
    ]));

    final restored = MissionState()..loadFromJsonString(m.toJsonString());

    expect(restored.missionName, 'Flood 2026');
    expect(restored.challenges, contains('night ops'));
    expect(restored.area, hasLength(3));
    expect(restored.personnelCount, 12);
    expect(restored.spareBatteries, 6);
    expect(restored.drones, hasLength(2));
    expect(restored.modules.single.attachedTo, "Ann's drone");
    expect(restored.specsFor(restored.drones.first)?.apRangeM, 400);
    expect(restored.deployments.single.placements.single.role, kRoleMeshRelay);
    expect(restored.activeDeployment?.name, 'plan A');
  });

  test('a module cannot be attached to two drones', () {
    final m = MissionState();
    m.addModule(ModuleResource(unitId: 'DCM-B-1', label: 'B'));
    expect(m.addDrone(DroneResource(label: 'd1', attachedModuleId: 'DCM-B-1')),
        isNull);
    // Second drone claiming the same module is rejected.
    expect(m.addDrone(DroneResource(label: 'd2', attachedModuleId: 'DCM-B-1')),
        contains('already on d1'));
    // Removing d1 frees the module.
    m.removeDrone(m.drones.first);
    expect(m.modules.single.attachedTo, isEmpty);
  });

  test('legacy operation-plan file imports as one approved deployment', () {
    final legacy = jsonEncode({
      'plan_name': 'old flood plan',
      'markers': [
        {'name': 'drone here', 'lat': 6.91, 'lon': 79.86, 'radius_m': 300},
        {'name': 'staging', 'lat': 6.95, 'lon': 79.90, 'radius_m': 150},
      ],
    });

    final m = MissionState()..loadFromJsonString(legacy);

    expect(m.missionName, 'old flood plan');
    expect(m.deployments, hasLength(1));
    final d = m.deployments.single;
    expect(d.approved, isTrue);
    expect(d.placements, hasLength(2));
    expect(d.placements[0].name, 'drone here');
    expect(d.placements[1].radiusM, 150);
    expect(m.activeDeploymentName, d.name);
  });

  test('save and load through a real file, then reject junk', () async {
    final dir = await Directory.systemTemp.createTemp('gcc_mission_');
    final path = '${dir.path}/mission.json';
    final m = MissionState()..setMissionInfo(name: 'quake');
    expect(await m.saveToFile(path), isNull);

    final restored = MissionState();
    expect(await restored.loadFromFile(path), isNull);
    expect(restored.missionName, 'quake');
    expect(restored.loadedFrom, path);

    final junk = '${dir.path}/junk.json';
    File(junk).writeAsStringSync('not json at all');
    expect(await restored.loadFromFile(junk), contains('Not a valid mission'));
  });

  test('ensureActiveDeployment and placement editing', () {
    final m = MissionState();
    final d = m.ensureActiveDeployment();
    expect(m.deployments, contains(d));
    m.addPlacement(DronePlacement(name: 'p', lat: 1, lon: 2, radiusM: 100));
    expect(d.placements, hasLength(1));
    m.movePlacement(d.placements.first, 3, 4);
    expect(d.placements.first.lat, 3);
    m.removePlacement(d.placements.first);
    expect(d.placements, isEmpty);
  });
}
