/// Token expiry must survive the two clocks disagreeing.
///
/// A node with no GPS fix runs on relative time restored from its last
/// shutdown, so it can be hours or days behind a phone. The token's
/// deadline is set on the NODE's clock. Comparing that against the
/// PHONE's clock made freshly issued tokens look already expired, so the
/// app dropped the session every time it was reopened, which testers
/// reported as being logged out.
library;

import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:test/test.dart';

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _loginResponse({
  required int serverNow,
  int ttlSeconds = 24 * 3600,
}) =>
    {
      'token': 'abc.def',
      'expires_at': serverNow + ttlSeconds,
      'server_time': serverNow,
      'personnel_id': 'RESC-01',
      'role': 'RESCUE_TEAM',
      'name': 'A. Perera',
    };

void main() {
  test('a token from a node running two days behind is NOT expired', () {
    // The exact reported case.
    final nodeClock = _now() - (2 * 24 * 3600);
    final s = AuthSession.fromLoginResponse(_loginResponse(serverNow: nodeClock));

    expect(s.expiresAt, lessThan(_now()),
        reason: 'the node\'s own deadline is in our past, as expected');
    expect(s.isExpired, isFalse,
        reason: 'but it has 24h of LIFETIME left, so the session must hold');
  });

  test('a token from a node running ahead is not given extra life', () {
    final nodeClock = _now() + (2 * 24 * 3600);
    final s = AuthSession.fromLoginResponse(_loginResponse(serverNow: nodeClock));
    expect(s.isExpired, isFalse);
    // Lifetime is 24h from now HERE, not 3 days.
    expect(s.localExpiresAt, closeTo(_now() + 24 * 3600, 5));
  });

  test('a genuinely spent token is still expired', () {
    final nodeClock = _now();
    final s = AuthSession.fromLoginResponse(
        _loginResponse(serverNow: nodeClock, ttlSeconds: -60));
    expect(s.isExpired, isTrue,
        reason: 'clock tolerance must not resurrect a dead token');
  });

  test('the local deadline survives being saved and reloaded', () {
    final nodeClock = _now() - (2 * 24 * 3600);
    final original =
        AuthSession.fromLoginResponse(_loginResponse(serverNow: nodeClock));
    final reloaded = AuthSession.fromJson(original.toJson());

    expect(reloaded.localExpiresAt, original.localExpiresAt);
    expect(reloaded.isExpired, isFalse,
        reason: 'reopening the app must not drop a valid session');
  });

  test('an older node that sends no server_time still works', () {
    final json = _loginResponse(serverNow: _now())..remove('server_time');
    final s = AuthSession.fromLoginResponse(json);
    expect(s.localExpiresAt, 0, reason: 'unknown, so fall back');
    expect(s.isExpired, isFalse);
  });
}
