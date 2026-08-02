import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/app_state.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  _portalVersionTests();
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings persist through SharedPreferences', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();

    await app.updateSettings(
      newBaseUrl: 'https://10.42.0.1:8443',
      newApiKey: 'bg_key',
      newMbtilesPath: '/maps/region.mbtiles',
      newMavlinkTarget: 'udp:10.99.0.3:14550',
    );

    final reloaded = AppState();
    await reloaded.load();
    expect(reloaded.baseUrl, 'https://10.42.0.1:8443');
    expect(reloaded.apiKey, 'bg_key');
    expect(reloaded.mbtilesPath, '/maps/region.mbtiles');
    expect(reloaded.mavlinkTarget, 'udp:10.99.0.3:14550');
  });

  test('session persists and expired sessions are dropped on load', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();
    expect(app.isLoggedIn, isFalse);
    expect(app.operatorLabel, 'not logged in');

    // Simulate a stored valid session.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    SharedPreferences.setMockInitialValues({
      'session_json':
          '{"token":"t.x","expires_at":${now + 3600},"personnel_id":"H-001","role":"HQ","name":"Op"}',
    });
    final withSession = AppState();
    await withSession.load();
    expect(withSession.isLoggedIn, isTrue);
    expect(withSession.isHq, isTrue);
    expect(withSession.operatorLabel, contains('H-001'));

    // Expired sessions are cleared at load.
    SharedPreferences.setMockInitialValues({
      'session_json':
          '{"token":"t.x","expires_at":${now - 10},"personnel_id":"H-001","role":"HQ","name":"Op"}',
    });
    final expired = AppState();
    await expired.load();
    expect(expired.isLoggedIn, isFalse);
  });

  test('isHq: HQ session, break-glass key, or neither', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();
    expect(app.isHq, isFalse);
    await app.updateSettings(newApiKey: 'some_key');
    expect(app.isHq, isTrue); // break-glass path
    app.session = const AuthSession(
        token: 't',
        expiresAt: 9999999999,
        personnelId: 'R-001',
        role: 'RESCUE_TEAM',
        name: 'r');
    expect(app.isHq, isFalse); // rescue session outranks the stored key
  });

  test('client is rebuilt when settings change', () async {
    SharedPreferences.setMockInitialValues({});
    final app = AppState();
    await app.load();
    final before = app.client;
    await app.updateSettings(newBaseUrl: 'https://10.42.0.2:8443');
    expect(identical(before, app.client), isFalse);
  });
}

/// Version allocation for victim-portal config pushes.
///
/// The bug this prevents: the counter originally lived in the mission file,
/// which the operator saves by hand. Push, forget to save, restart, and the
/// counter rewinds. Every later push is then rejected as stale by nodes
/// that already advanced, with no visible cause. It now lives in prefs
/// (persisted the instant it changes) AND is reconciled against what the
/// target node reports, so it self-heals even on a fresh install.
void _portalVersionTests() {
  group('portal config version allocation', () {
    test('first push to a stock node is v1', () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState();
      await app.load();
      expect(await app.claimPortalConfigVersion(0), 1);
    });

    test('the counter persists immediately, with no manual save', () async {
      SharedPreferences.setMockInitialValues({});
      final a = AppState();
      await a.load();
      await a.claimPortalConfigVersion(0);
      await a.claimPortalConfigVersion(0);

      // A brand new instance, as after a restart.
      final b = AppState();
      await b.load();
      expect(b.portalConfigVersion, 2,
          reason: 'restart must not rewind the counter');
      expect(await b.claimPortalConfigVersion(0), 3);
    });

    test('a node ahead of us pulls the counter forward', () async {
      // Fresh install, or a second operator laptop, against a node another
      // machine already pushed v7 to.
      SharedPreferences.setMockInitialValues({});
      final app = AppState();
      await app.load();
      expect(await app.claimPortalConfigVersion(7), 8,
          reason: 'must beat the node, not restart from 1 and be rejected');
    });

    test('our counter wins when the node is behind', () async {
      SharedPreferences.setMockInitialValues({'portal_config_version': 9});
      final app = AppState();
      await app.load();
      // Pushing to a node still on stock must not reuse an old number,
      // otherwise two different configs would both be called v1.
      expect(await app.claimPortalConfigVersion(0), 10);
    });

    test('always strictly increases across mixed nodes', () async {
      SharedPreferences.setMockInitialValues({});
      final app = AppState();
      await app.load();
      var last = 0;
      for (final nodeVersion in [0, 3, 0, 11, 2, 0]) {
        final v = await app.claimPortalConfigVersion(nodeVersion);
        expect(v, greaterThan(last));
        expect(v, greaterThan(nodeVersion),
            reason: 'the node must accept it');
        last = v;
      }
    });
  });
}
