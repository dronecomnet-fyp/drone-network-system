import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/mission_state.dart';

void main() {
  _attachConsistencyTests();
  _portalOptionTests();
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

/// Victim-portal options: defaults, and the single permitted edit.
///
/// The one-edit rule is the operator's decision (field backlog #7), taken
/// over free editing because several revisions in play make "which options
/// is this node serving" hard to reason about. It locks EDITING only:
/// pushing still happens once per drone.
void _portalOptionTests() {
  group('portal options', () {
    test('a fresh mission uses defaults and is editable', () {
      final m = MissionState();
      expect(m.portalOptions, isEmpty);
      expect(m.canEditPortalOptions, isTrue);
    });

    test('editing once takes effect and then locks', () {
      final m = MissionState();
      m.setPortalOptions([
        {'id': 'trapped', 'label': 'Water is rising here', 'urgent': true},
      ]);
      expect(m.portalOptions.single['label'], 'Water is rising here');
      expect(m.canEditPortalOptions, isFalse);
    });

    test('a second edit is ignored, not silently applied', () {
      final m = MissionState();
      m.setPortalOptions([
        {'id': 'a', 'label': 'First wording', 'urgent': true},
      ]);
      m.setPortalOptions([
        {'id': 'a', 'label': 'Second wording', 'urgent': true},
      ]);
      expect(m.portalOptions.single['label'], 'First wording',
          reason: 'the lock must actually hold, not just hide the button');
    });

    test('an empty edit cannot wipe what victims see', () {
      final m = MissionState();
      m.setPortalOptions([]);
      expect(m.portalOptions, isEmpty);
      expect(m.canEditPortalOptions, isTrue,
          reason: 'a no-op must not consume the single edit');
    });

    test('the edit and its lock survive a save and load', () {
      final m = MissionState();
      m.setPortalOptions([
        {'id': 'roof', 'label': 'We are on the roof', 'urgent': true},
      ]);
      final json = m.toJsonString();

      final loaded = MissionState()..loadFromJsonString(json);
      expect(loaded.portalOptions.single['label'], 'We are on the roof');
      expect(loaded.canEditPortalOptions, isFalse,
          reason: 'reloading the mission must not hand back a second edit');
    });
  });
}

/// Module attach/detach consistency (field backlog #2).
///
/// Both the drone list and the module list show this relationship, but only
/// the drone side could change it, so it read like two settings that might
/// disagree. Whichever side breaks the link, both must end up telling the
/// same story.
void _attachConsistencyTests() {
  group('module attachment stays consistent', () {
    MissionState withPair() {
      final m = MissionState();
      m.addModule(ModuleResource(unitId: 'DCM-A-0042', label: 'module B'));
      m.addDrone(DroneResource(
        label: "Ann's drone",
        source: 'volunteer',
        attachedModuleId: 'DCM-A-0042',
      ));
      return m;
    }

    test('attaching is visible from both sides', () {
      final m = withPair();
      expect(m.drones.single.attachedModuleId, 'DCM-A-0042');
      expect(m.modules.single.attachedTo, "Ann's drone");
    });

    test('detaching from the module side clears both sides', () {
      final m = withPair();
      m.detachModuleByUnitId('DCM-A-0042');
      expect(m.modules.single.attachedTo, isEmpty);
      expect(m.drones.single.attachedModuleId, isEmpty,
          reason: 'the drone must not still claim a module it no longer has');
    });

    test('detaching from the drone side clears both sides', () {
      final m = withPair();
      m.detachModule(m.drones.single);
      expect(m.drones.single.attachedModuleId, isEmpty);
      expect(m.modules.single.attachedTo, isEmpty);
    });

    test('the module returns to the free pool after detaching', () {
      final m = withPair();
      m.detachModuleByUnitId('DCM-A-0042');
      final free = m.modules.where((x) => x.attachedTo.isEmpty).length;
      expect(free, 1, reason: 'it must be offerable to another drone again');
    });

    test('detaching an unknown id is harmless', () {
      final m = withPair();
      m.detachModuleByUnitId('NOT-A-MODULE');
      expect(m.modules.single.attachedTo, "Ann's drone");
    });
  });
}
