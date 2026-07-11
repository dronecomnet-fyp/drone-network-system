/// AppState: settings, session, and the API client lifecycle.
///
/// Connectivity model (file 04, stated in the UI): the GCC laptop joins
/// whichever drone AP is in range and talks to that ONE node; its view of
/// other nodes is only as fresh as DTN sync plus fallback beacons, so
/// every dataset carries a last-updated age instead of pretending to be
/// live.
///
/// Auth (file 09 plane 2): HQ operators log in with personnel_id + PIN
/// like everyone else; the static HQ key is a break-glass credential,
/// clearly labeled in Settings.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppState extends ChangeNotifier {
  static const _kBaseUrl = 'base_url';
  static const _kApiKey = 'hq_api_key';
  static const _kCaPem = 'fleet_ca_pem';
  static const _kAllowInsecure = 'allow_insecure';
  static const _kMbtilesPath = 'mbtiles_path';
  static const _kSession = 'session_json';
  static const _kMavlinkTarget = 'mavlink_target';
  static const _kCoverageRadiusM = 'coverage_radius_m';

  SharedPreferences? _prefs;

  String baseUrl = 'https://10.42.0.1:8443';
  String apiKey = '';
  String fleetCaPem = '';
  bool allowInsecure = false;
  String mbtilesPath = '';

  /// MAVLink target for the drone control tab (file 08 presets):
  /// DIRECT = 10.42.0.1:14550 (laptop on RESCUE_S),
  /// MESH RELAY = 10.99.0.3:14550 (laptop on a volunteer AP).
  String mavlinkTarget = 'udp:10.42.0.1:14550';
  double coverageRadiusM = 300;

  AuthSession? session;
  RescueMeshClient? _client;

  bool get isLoggedIn => session != null && !session!.isExpired;
  bool get isHq =>
      (session?.role == 'HQ') || (session == null && apiKey.isNotEmpty);
  String get operatorLabel => session != null
      ? '${session!.personnelId} (${session!.role})'
      : (apiKey.isNotEmpty ? 'break-glass key' : 'not logged in');

  RescueMeshClient get client {
    _client ??= _buildClient();
    return _client!;
  }

  RescueMeshClient _buildClient() => RescueMeshClient(
        baseUrl: baseUrl,
        fleetCaPem: fleetCaPem.isEmpty ? null : fleetCaPem,
        allowInsecure: allowInsecure,
        sessionToken: session?.token,
        apiKey: apiKey.isEmpty ? null : apiKey,
      );

  void _rebuildClient() {
    _client?.close();
    _client = null;
    notifyListeners();
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    baseUrl = p.getString(_kBaseUrl) ?? baseUrl;
    apiKey = p.getString(_kApiKey) ?? '';
    fleetCaPem = p.getString(_kCaPem) ?? '';
    allowInsecure = p.getBool(_kAllowInsecure) ?? false;
    mbtilesPath = p.getString(_kMbtilesPath) ?? '';
    mavlinkTarget = p.getString(_kMavlinkTarget) ?? mavlinkTarget;
    coverageRadiusM = p.getDouble(_kCoverageRadiusM) ?? coverageRadiusM;
    final sessionJson = p.getString(_kSession);
    if (sessionJson != null && sessionJson.isNotEmpty) {
      try {
        session = AuthSession.fromStoredJson(
            jsonDecode(sessionJson) as Map<String, dynamic>);
        if (session!.isExpired) session = null;
      } catch (_) {
        session = null;
      }
    }
    notifyListeners();
  }

  Future<void> updateSettings({
    String? newBaseUrl,
    String? newApiKey,
    String? newCaPem,
    bool? newAllowInsecure,
    String? newMbtilesPath,
    String? newMavlinkTarget,
    double? newCoverageRadiusM,
  }) async {
    final p = _prefs;
    if (newBaseUrl != null) {
      baseUrl = newBaseUrl.trim();
      await p?.setString(_kBaseUrl, baseUrl);
    }
    if (newApiKey != null) {
      apiKey = newApiKey.trim();
      await p?.setString(_kApiKey, apiKey);
    }
    if (newCaPem != null) {
      fleetCaPem = newCaPem;
      await p?.setString(_kCaPem, fleetCaPem);
    }
    if (newAllowInsecure != null) {
      allowInsecure = newAllowInsecure;
      await p?.setBool(_kAllowInsecure, allowInsecure);
    }
    if (newMbtilesPath != null) {
      mbtilesPath = newMbtilesPath;
      await p?.setString(_kMbtilesPath, mbtilesPath);
    }
    if (newMavlinkTarget != null) {
      mavlinkTarget = newMavlinkTarget;
      await p?.setString(_kMavlinkTarget, mavlinkTarget);
    }
    if (newCoverageRadiusM != null) {
      coverageRadiusM = newCoverageRadiusM;
      await p?.setDouble(_kCoverageRadiusM, coverageRadiusM);
    }
    _rebuildClient();
  }

  Future<String?> loadCaFromFile(String path) async {
    try {
      final pem = await File(path).readAsString();
      if (!pem.contains('BEGIN CERTIFICATE')) {
        return 'Not a PEM certificate file';
      }
      await updateSettings(newCaPem: pem);
      return null;
    } on FileSystemException catch (e) {
      return 'Could not read file: ${e.message}';
    }
  }

  Future<String?> login(String personnelId, String pin) async {
    try {
      final s = await client.login(personnelId, pin);
      session = s;
      await _prefs?.setString(_kSession, jsonEncode(s.toJson()));
      _rebuildClient();
      return null;
    } on ApiException catch (e) {
      return e.isRateLimited
          ? 'Too many attempts; wait a bit and retry.'
          : 'Login failed: ${e.detail}';
    } on SocketException {
      return 'Cannot reach the node. Join a RESCUE_x WiFi first.';
    } on HandshakeException {
      return 'TLS rejected: the node cert does not chain to the loaded '
          'fleet CA (possible evil twin, or CA not loaded in Settings).';
    }
  }

  Future<void> logout() async {
    session = null;
    await _prefs?.remove(_kSession);
    _rebuildClient();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
