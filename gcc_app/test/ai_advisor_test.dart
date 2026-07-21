import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/services/ai_advisor.dart';
import 'package:gcc_app/state/mission_state.dart';

// A square operation area around (6.90, 79.85), ~1.1 km per side.
MissionState _mission() {
  final m = MissionState();
  m.addAreaVertex(6.895, 79.845);
  m.addAreaVertex(6.905, 79.845);
  m.addAreaVertex(6.905, 79.855);
  m.addAreaVertex(6.895, 79.855);
  m.addDrone(DroneResource(label: 'd1'));
  m.addDrone(DroneResource(label: 'd2'));
  m.cacheProduct(
      'x',
      const ProductInfo(
        modelNo: 'DCM',
        name: 'module',
        specs: {'ap_range_m': 300, 'mesh_range_m': 900},
        fetchedAt: '2026-07-21T00:00:00Z',
      ));
  return m;
}

void main() {
  group('parseSuggestionJson', () {
    test('parses a bare JSON object', () {
      final raw = parseSuggestionJson('{"placements":[],"summary":"hi"}');
      expect(raw['summary'], 'hi');
    });

    test('strips ```json code fences', () {
      const reply = '```json\n{"placements":[{"name":"a"}]}\n```';
      final raw = parseSuggestionJson(reply);
      expect((raw['placements'] as List), hasLength(1));
    });

    test('slices JSON out of surrounding prose', () {
      const reply =
          'Sure! Here is the plan: {"placements":[],"summary":"ok"} Hope it helps.';
      final raw = parseSuggestionJson(reply);
      expect(raw['summary'], 'ok');
    });

    test('throws on non-JSON (a refusal)', () {
      expect(() => parseSuggestionJson('I cannot help with that.'),
          throwsFormatException);
    });
  });

  group('validateSuggestion', () {
    test('accepts in-area, connected placements with no warnings', () {
      final m = _mission();
      final raw = {
        'summary': 'two nodes',
        'placements': [
          {'name': 'ap', 'lat': 6.899, 'lon': 79.849, 'role': 'user_ap', 'radius_m': 300},
          {'name': 'relay', 'lat': 6.901, 'lon': 79.851, 'role': 'mesh_relay', 'radius_m': 400},
        ],
      };
      final s = validateSuggestion(raw, m);
      expect(s.placements, hasLength(2));
      expect(s.summary, 'two nodes');
      expect(s.warnings, isEmpty);
    });

    test('warns when a placement is outside the area', () {
      final m = _mission();
      final raw = {
        'placements': [
          {'name': 'far', 'lat': 7.5, 'lon': 80.5, 'role': 'user_ap', 'radius_m': 300},
        ],
      };
      final s = validateSuggestion(raw, m);
      expect(s.warnings.any((w) => w.contains('outside the operation area')),
          isTrue);
    });

    test('warns when placements exceed available drones', () {
      final m = _mission(); // 2 drones
      final raw = {
        'placements': [
          for (var i = 0; i < 4; i++)
            {'name': 'n$i', 'lat': 6.900, 'lon': 79.850, 'role': 'user_ap', 'radius_m': 300},
        ],
      };
      final s = validateSuggestion(raw, m);
      expect(s.warnings.any((w) => w.contains('only 2 drones')), isTrue);
    });

    test('warns on a disconnected placement (out of mesh range)', () {
      final m = _mission(); // mesh range 900 m
      final raw = {
        'placements': [
          {'name': 'a', 'lat': 6.8951, 'lon': 79.8451, 'role': 'mesh_relay', 'radius_m': 300},
          {'name': 'b', 'lat': 6.9049, 'lon': 79.8549, 'role': 'mesh_relay', 'radius_m': 300},
        ],
      };
      // The two corners are ~1.5 km apart, beyond the 900 m mesh range.
      final s = validateSuggestion(raw, m);
      expect(s.warnings.any((w) => w.contains('out of mesh range')), isTrue);
    });

    test('warns on more than one system drone', () {
      final m = _mission();
      final raw = {
        'placements': [
          {'name': 's1', 'lat': 6.900, 'lon': 79.850, 'role': 'system_drone', 'radius_m': 300},
          {'name': 's2', 'lat': 6.901, 'lon': 79.851, 'role': 'system_drone', 'radius_m': 300},
        ],
      };
      final s = validateSuggestion(raw, m);
      expect(s.warnings.any((w) => w.contains('one system-drone')), isTrue);
    });

    test('clamps radius and defaults an unknown role', () {
      final m = _mission();
      final raw = {
        'placements': [
          {'name': 'p', 'lat': 6.900, 'lon': 79.850, 'role': 'nonsense', 'radius_m': 99999},
        ],
      };
      final s = validateSuggestion(raw, m);
      expect(s.placements.single.role, kRoleUserAp);
      expect(s.placements.single.radiusM, lessThanOrEqualTo(5000));
    });

    test('throws when there are no usable placements', () {
      final m = _mission();
      expect(() => validateSuggestion({'placements': []}, m),
          throwsFormatException);
      expect(
          () => validateSuggestion({
                'placements': [
                  {'name': 'x'} // no coords
                ]
              }, m),
          throwsFormatException);
    });
  });

  test('buildUserPrompt includes the area and counts', () {
    final m = _mission();
    m.setMissionInfo(name: 'Flood 2026', type: 'flood');
    final prompt = buildUserPrompt(m);
    expect(prompt, contains('Flood 2026'));
    expect(prompt, contains('Available drones: 2'));
    expect(prompt, contains('6.895000, 79.845000'));
  });
}
