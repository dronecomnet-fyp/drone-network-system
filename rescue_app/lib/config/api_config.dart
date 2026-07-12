import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';

class AppApiConfig {
  final String baseUrl;

  /// Break-glass static key (file 09 plane 2: demoted; PIN login is the
  /// normal path). Optional.
  final String apiKey;
  final String rescuePrivateKey;

  /// Fleet CA certificate PEM for real pinning (file 09 F1). HTTPS fails
  /// closed without it.
  final String fleetCaPem;

  /// Dev/bench only; defeats evil-twin protection and is labeled as such.
  final bool allowInsecure;

  const AppApiConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.rescuePrivateKey,
    required this.fleetCaPem,
    required this.allowInsecure,
  });

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  bool get hasPrivateKey => rescuePrivateKey.trim().isNotEmpty;

  bool get hasFleetCa => fleetCaPem.trim().isNotEmpty;
}

class ApiConfigStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String _keyBaseUrl = 'api_base_url';
  static const String _keyApiKey = 'rescue_api_key';
  static const String _keyPrivateKey = 'rescue_private_key';
  static const String _keyFleetCa = 'fleet_ca_pem';
  static const String _keyAllowInsecure = 'allow_insecure_tls';

  static const String _defaultBaseUrl = 'https://10.42.0.1:8443';

  static Future<AppApiConfig> load() async {
    final savedBaseUrl = await _storage.read(key: _keyBaseUrl);
    final savedApiKey = await _storage.read(key: _keyApiKey);
    final savedPrivateKey = await _storage.read(key: _keyPrivateKey);
    final savedFleetCa = await _storage.read(key: _keyFleetCa);
    final savedAllowInsecure = await _storage.read(key: _keyAllowInsecure);

    return AppApiConfig(
      baseUrl: (savedBaseUrl == null || savedBaseUrl.trim().isEmpty)
          ? _defaultBaseUrl
          : savedBaseUrl.trim(),
      apiKey: (savedApiKey ?? '').trim(),
      rescuePrivateKey: (savedPrivateKey ?? '').trim(),
      fleetCaPem: (savedFleetCa ?? '').trim(),
      allowInsecure: savedAllowInsecure == 'true',
    );
  }

  static Future<void> save({
    required String baseUrl,
    required String apiKey,
    required String rescuePrivateKey,
    required String fleetCaPem,
    required bool allowInsecure,
  }) async {
    await _storage.write(key: _keyBaseUrl, value: baseUrl.trim());
    await _storage.write(key: _keyApiKey, value: apiKey.trim());
    await _storage.write(key: _keyPrivateKey, value: rescuePrivateKey.trim());
    await _storage.write(key: _keyFleetCa, value: fleetCaPem.trim());
    await _storage.write(
        key: _keyAllowInsecure, value: allowInsecure ? 'true' : 'false');
  }

  static bool isValidHttpUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) {
      return false;
    }
    final hasValidScheme = uri.scheme == 'http' || uri.scheme == 'https';
    final hasHost = uri.host.isNotEmpty;
    final hasPort = uri.hasPort;
    return hasValidScheme && hasHost && hasPort;
  }
}

/// Session token storage (file 05 task 5.1): {token, expires_at,
/// personnel_id, role, name} in secure storage, verified offline-capable
/// by ANY node because tokens are HMAC-signed fleet-wide.
class SessionStore {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keySession = 'session_json';

  static Future<AuthSession?> load() async {
    final raw = await _storage.read(key: _keySession);
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final session =
          AuthSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (session.isExpired) {
        await clear();
        return null;
      }
      return session;
    } catch (_) {
      await clear();
      return null;
    }
  }

  static Future<void> save(AuthSession session) async {
    await _storage.write(
        key: _keySession, value: jsonEncode(session.toJson()));
  }

  static Future<void> clear() async {
    await _storage.delete(key: _keySession);
  }
}
