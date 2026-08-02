import 'package:flutter_test/flutter_test.dart';
import 'package:gcc_app/state/app_state.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
