import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/plan_state.dart';

void main() {
  test('markers add/remove/clear notify and mutate', () {
    final plan = PlanState();
    var notifications = 0;
    plan.addListener(() => notifications++);

    final m = PlanMarker(name: 'lz alpha', lat: 6.9, lon: 79.8, radiusM: 250);
    plan.addMarker(m);
    expect(plan.markers, hasLength(1));
    plan.removeMarker(m);
    expect(plan.markers, isEmpty);
    plan.addMarker(m);
    plan.clear();
    expect(plan.markers, isEmpty);
    expect(notifications, 4);
  });

  test('plan JSON round trip preserves markers (file 04 acceptance 4)', () {
    final plan = PlanState();
    plan.planName = 'flood response north';
    plan.addMarker(
        PlanMarker(name: 'place drone here', lat: 6.91, lon: 79.86, radiusM: 300));
    plan.addMarker(
        PlanMarker(name: 'staging', lat: 6.95, lon: 79.90, radiusM: 150));

    final json = plan.toJsonString();
    final restored = PlanState()..loadFromJsonString(json);

    expect(restored.planName, 'flood response north');
    expect(restored.markers, hasLength(2));
    expect(restored.markers[0].name, 'place drone here');
    expect(restored.markers[0].lat, 6.91);
    expect(restored.markers[1].radiusM, 150);
  });

  test('save and load through a real file', () async {
    final dir = await Directory.systemTemp.createTemp('gcc_plan_');
    final path = '${dir.path}/plan.json';
    final plan = PlanState();
    plan.addMarker(PlanMarker(name: 'x', lat: 1.0, lon: 2.0, radiusM: 100));

    expect(await plan.saveToFile(path), isNull);
    final restored = PlanState();
    expect(await restored.loadFromFile(path), isNull);
    expect(restored.markers.single.name, 'x');
    expect(restored.loadedFrom, path);
  });

  test('loading a non-plan file reports an error instead of throwing',
      () async {
    final dir = await Directory.systemTemp.createTemp('gcc_plan_');
    final path = '${dir.path}/junk.json';
    File(path).writeAsStringSync('this is not json');
    final plan = PlanState();
    expect(await plan.loadFromFile(path), contains('Not a valid plan file'));
    expect(await plan.loadFromFile('${dir.path}/missing.json'),
        contains('Load failed'));
  });
}
