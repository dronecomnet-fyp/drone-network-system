/// RescueMeshClient: the one HTTP client for all three apps (file 04).
///
/// TLS trust (file 09 F1, plane 2): when a fleet CA certificate is
/// supplied, the client trusts ONLY that root (no system roots) and
/// rejects everything else via a fail-closed badCertificateCallback.
/// Phase 1's accept-any-certificate-for-10.42.0.1 behavior is gone: an
/// evil twin presenting its own self-signed cert cannot authenticate.
///
/// Auth precedence mirrors the backend (backend/api.py get_auth):
///   1. session token (X-Session-Token) from PIN login
///   2. break-glass static key (X-API-Key), clearly labeled in the UIs
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models.dart';

class ApiException implements Exception {
  final int statusCode;
  final String detail;

  const ApiException(this.statusCode, this.detail);

  bool get isAuthFailure => statusCode == 401 || statusCode == 403;
  bool get isRevoked => statusCode == 403;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'ApiException($statusCode): $detail';
}

class RescueMeshClient {
  /// e.g. https://10.42.0.1:8443
  final String baseUrl;

  /// Fleet CA certificate (PEM). Required for https URLs unless
  /// [allowInsecure] is explicitly set (dev/test only).
  final String? fleetCaPem;

  /// Dev/test escape hatch: accept any certificate. NEVER ship enabled;
  /// the UIs must label it as insecure when toggled.
  final bool allowInsecure;

  String? sessionToken;
  String? apiKey;

  final Duration timeout;
  late final http.Client _http;

  RescueMeshClient({
    required this.baseUrl,
    this.fleetCaPem,
    this.allowInsecure = false,
    this.sessionToken,
    this.apiKey,
    this.timeout = const Duration(seconds: 8),
  }) {
    _http = _buildClient();
  }

  http.Client _buildClient() {
    if (!baseUrl.startsWith('https')) {
      return http.Client();
    }
    final ctx = SecurityContext(withTrustedRoots: false);
    if (fleetCaPem != null && fleetCaPem!.trim().isNotEmpty) {
      ctx.setTrustedCertificatesBytes(utf8.encode(fleetCaPem!));
    }
    final inner = HttpClient(context: ctx)
      ..connectionTimeout = timeout
      // Fail closed: anything not chaining to the fleet CA is rejected,
      // unless the dev-only insecure flag is set (file 09 T9.1).
      ..badCertificateCallback = (cert, host, port) => allowInsecure;
    return IOClient(inner);
  }

  Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    final token = sessionToken;
    final key = apiKey;
    if (token != null && token.isNotEmpty) {
      h['X-Session-Token'] = token;
    } else if (key != null && key.isNotEmpty) {
      h['X-API-Key'] = key;
    }
    return h;
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    final resp = await _http
        .get(_uri(path, query), headers: _headers(json: false))
        .timeout(timeout);
    return _decode(resp);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final resp = await _http
        .post(_uri(path), headers: _headers(), body: jsonEncode(body))
        .timeout(timeout);
    return _decode(resp);
  }

  dynamic _decode(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return resp.body.isEmpty ? null : jsonDecode(resp.body);
    }
    String detail;
    try {
      final body = jsonDecode(resp.body);
      detail = (body is Map && body['detail'] != null)
          ? '${body['detail']}'
          : resp.body;
    } catch (_) {
      detail = resp.body;
    }
    throw ApiException(resp.statusCode, detail);
  }

  // --- auth ----------------------------------------------------------------

  /// PIN login. On success the returned session is ALSO installed on this
  /// client (subsequent calls send the token).
  Future<AuthSession> login(String personnelId, String pin) async {
    final data = await _post('/auth/login', {
      'personnel_id': personnelId,
      'pin': pin,
    });
    final session = AuthSession.fromJson(data as Map<String, dynamic>);
    sessionToken = session.token;
    return session;
  }

  void logout() {
    sessionToken = null;
  }

  // --- messages --------------------------------------------------------------

  Future<List<Message>> getMessages({String? victimDeviceId}) async {
    final data = await _get('/messages',
        query: victimDeviceId == null
            ? null
            : {'victim_device_id': victimDeviceId});
    return (data as List<dynamic>)
        .map((m) => Message.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<String> postMessage(String content,
      {double? userLat, double? userLon, String victimDeviceId = ''}) async {
    final data = await _post('/messages', {
      'content': content,
      'user_lat': userLat,
      'user_lon': userLon,
      'victim_device_id': victimDeviceId,
    });
    return (data as Map<String, dynamic>)['msg_id'] as String;
  }

  /// Claim a message. [claimedBy] is only used on the break-glass key
  /// path; token identity always wins server-side (file 05 task 5.2).
  Future<Map<String, dynamic>> claimMessage(String msgId,
      {String claimedBy = ''}) async {
    final data = await _post('/messages/$msgId/claim', {
      if (claimedBy.isNotEmpty) 'claimed_by': claimedBy,
    });
    return data as Map<String, dynamic>;
  }

  // --- gs messages -----------------------------------------------------------

  Future<List<GsMessage>> getGsMessages() async {
    final data = await _get('/gs-messages');
    return (data as List<dynamic>)
        .map((m) => GsMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<String> postGsUplink(String content,
      {String sender = '',
      double? locationLat,
      double? locationLon,
      double? locationAccuracy}) async {
    final data = await _post('/gs-uplink', {
      'content': content,
      if (sender.isNotEmpty) 'sender': sender,
      'location_lat': locationLat,
      'location_lon': locationLon,
      'location_accuracy': locationAccuracy,
    });
    return (data as Map<String, dynamic>)['msg_id'] as String;
  }

  // --- announcements -----------------------------------------------------------

  Future<List<Announcement>> getAnnouncements() async {
    final data = await _get('/announcements');
    return (data as List<dynamic>)
        .map((a) => Announcement.fromJson(a as Map<String, dynamic>))
        .toList();
  }

  Future<String> postAnnouncement(String title, String body,
      {String priority = 'NORMAL'}) async {
    final data = await _post('/announcements', {
      'title': title,
      'body': body,
      'priority': priority,
    });
    return (data as Map<String, dynamic>)['id'] as String;
  }

  // --- personnel (HQ) ---------------------------------------------------------

  Future<List<Personnel>> getPersonnel() async {
    final data = await _get('/personnel');
    return (data as List<dynamic>)
        .map((p) => Personnel.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// Returns the one-time PIN; the caller shows it once and must not
  /// persist it (file 02 task 2.4).
  Future<IssuedPersonnel> createPersonnel(String name,
      {String role = 'RESCUE_TEAM', int expiresHours = 0}) async {
    final data = await _post('/personnel', {
      'name': name,
      'role': role,
      'expires_hours': expiresHours,
    });
    return IssuedPersonnel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> revokePersonnel(String personnelId) async {
    await _post('/personnel/$personnelId/revoke', {});
  }

  // --- victim plane probe -------------------------------------------------------

  /// Confirm this device is actually on a rescue drone AP (file 06). Build
  /// the client against the PUBLIC victim plane (http, port 80). Returns the
  /// node id (e.g. "DRONE_A") when a node answers, else null. Never throws:
  /// "not on a drone" is a normal answer, not an error.
  Future<String?> probeDrone() async {
    try {
      final data = await _get('/probe');
      if (data is Map<String, dynamic>) {
        return data['node_id'] as String?;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // --- checkins --------------------------------------------------------------

  /// Upload stored location points and an optional SOS from the emergency
  /// app (file 06). This is the PUBLIC victim plane (HTTP port 80): build
  /// the client with an http base URL (e.g. http://10.42.0.1) and no auth.
  /// An SOS also creates a rescue message server-side (file 02 task 2.5).
  /// Returns {stored, sos_msg_id}.
  Future<Map<String, dynamic>> postCheckin({
    required String deviceId,
    required List<Map<String, dynamic>> points,
    bool sos = false,
    String sosText = '',
  }) async {
    final data = await _post('/checkin', {
      'device_id': deviceId,
      'sos': sos,
      'sos_text': sosText,
      'points': points,
    });
    return data as Map<String, dynamic>;
  }

  Future<List<Checkin>> getCheckins() async {
    final data = await _get('/checkins');
    return (data as List<dynamic>)
        .map((c) => Checkin.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// Post the logged-in rescuer's location heartbeat (M7d). Identity is
  /// taken from the session token server-side; only coordinates travel.
  Future<void> postLocation(double lat, double lon,
      {double? accuracyM, int? batteryPct}) async {
    await _post('/personnel-location', {
      'lat': lat,
      'lon': lon,
      if (accuracyM != null) 'accuracy_m': accuracyM,
      if (batteryPct != null) 'battery_pct': batteryPct,
    });
  }

  /// The last known location of each rescuer (M7d), for the GCC map.
  Future<List<PersonnelLocation>> getPersonnelLocations() async {
    final data = await _get('/personnel-locations');
    return (data as List<dynamic>)
        .map((p) => PersonnelLocation.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  Future<NodeHealth> getHealth() async {
    final data = await _get('/health');
    return NodeHealth.fromJson(data as Map<String, dynamic>);
  }

  void close() {
    _http.close();
  }
}
