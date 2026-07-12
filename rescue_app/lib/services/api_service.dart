/// APIService: static facade the screens/providers call (Phase 1
/// architecture kept per file 05). Transport and JSON parsing now
/// delegate to the shared package (rescue_mesh_shared) so the wire
/// contract lives in ONE place for the GCC, this app, and the emergency
/// app (file 04).
///
/// TLS (file 09 F1): the Phase 1 badCertificateCallback that accepted ANY
/// certificate for 10.42.0.1 is gone. Connections trust ONLY the fleet CA
/// loaded in Settings and fail closed otherwise, so an evil twin
/// broadcasting a fake RESCUE_x cannot authenticate to this app.
///
/// Auth precedence (matches the backend): session token from PIN login
/// first; the break-glass X-API-Key from Settings as the labeled
/// admin/recovery fallback (file 05 task 5.1).
library;

import 'dart:async';
import 'dart:io';

import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../config/api_config.dart';
import '../models/api_error_model.dart';
import '../models/message_model.dart';

class APIService {
  static const Duration timeout = Duration(seconds: 10);

  static Future<shared.RescueMeshClient> _buildClient() async {
    final cfg = await ApiConfigStore.load();
    final session = await SessionStore.load();
    if (cfg.baseUrl.startsWith('https') &&
        !cfg.hasFleetCa &&
        !cfg.allowInsecure) {
      throw const ApiException(
        type: ApiErrorType.pinningFailed,
        message: 'No fleet CA loaded. Paste fleet_ca.crt in Settings '
            '(HTTPS fails closed without it, by design).',
      );
    }
    return shared.RescueMeshClient(
      baseUrl: cfg.baseUrl,
      fleetCaPem: cfg.hasFleetCa ? cfg.fleetCaPem : null,
      allowInsecure: cfg.allowInsecure,
      sessionToken: session?.token,
      apiKey: cfg.hasApiKey ? cfg.apiKey : null,
      timeout: timeout,
    );
  }

  static ApiException _mapError(Object error) {
    if (error is ApiException) {
      return error;
    }
    if (error is shared.ApiException) {
      switch (error.statusCode) {
        case 400:
          return ApiException(
            type: ApiErrorType.badRequest,
            statusCode: 400,
            message: 'Invalid request: ${error.detail}',
          );
        case 401:
          return ApiException(
            type: ApiErrorType.sessionExpired,
            statusCode: 401,
            message: 'Session expired or invalid. Log in again with your PIN.',
          );
        case 403:
          return ApiException(
            type: ApiErrorType.revoked,
            statusCode: 403,
            message: 'Credentials rejected: ${error.detail}. If revoked, '
                'HQ must issue new credentials.',
          );
        case 429:
          return const ApiException(
            type: ApiErrorType.rateLimited,
            statusCode: 429,
            message: 'Rate limit reached. Retrying with backoff.',
          );
        case 503:
          return const ApiException(
            type: ApiErrorType.serviceUnavailable,
            statusCode: 503,
            message: 'Service temporarily unavailable.',
          );
        default:
          if (error.statusCode >= 500) {
            return ApiException(
              type: ApiErrorType.serverError,
              statusCode: error.statusCode,
              message: 'Server error. Please retry shortly.',
            );
          }
          return ApiException(
            type: ApiErrorType.unknown,
            statusCode: error.statusCode,
            message: 'Unexpected response: ${error.detail}',
          );
      }
    }
    if (error is HandshakeException) {
      return const ApiException(
        type: ApiErrorType.pinningFailed,
        message: 'TLS rejected: node certificate does not chain to the '
            'loaded fleet CA (possible fake RESCUE_x network, or wrong CA '
            'in Settings).',
      );
    }
    if (error is TimeoutException) {
      return const ApiException(
        type: ApiErrorType.timeout,
        message: 'Request timed out. Check network and retry.',
      );
    }
    if (error is SocketException) {
      return ApiException(
        type: ApiErrorType.networkError,
        message: 'Cannot reach the drone. Join a RESCUE_x WiFi first. '
            '(${error.message})',
      );
    }
    return ApiException(
      type: ApiErrorType.unknown,
      message: 'Network error: $error',
    );
  }

  static Future<T> _run<T>(
      Future<T> Function(shared.RescueMeshClient client) action) async {
    shared.RescueMeshClient? client;
    try {
      client = await _buildClient();
      return await action(client);
    } catch (e) {
      throw _mapError(e);
    } finally {
      client?.close();
    }
  }

  // --- auth (file 05 task 5.1) -----------------------------------------------

  static Future<shared.AuthSession> login(String personnelId, String pin) {
    return _run((c) => c.login(personnelId, pin));
  }

  // --- messages -----------------------------------------------------------------

  static Future<List<Message>> getMessages() {
    return _run((c) async {
      final list = await c.getMessages();
      return list.map(Message.fromShared).toList();
    });
  }

  /// Claims a message; the backend stamps claimed_by from the session
  /// token identity (file 05 task 5.2). Returns the claimer recorded.
  static Future<String> claimMessage(String msgId) {
    return _run((c) async {
      final result = await c.claimMessage(msgId);
      return (result['claimed_by'] ?? '') as String;
    });
  }

  // --- gs uplink -----------------------------------------------------------------

  static Future<bool> submitGSUplink(String content, String sender,
      {double? locationLat,
      double? locationLon,
      double? locationAccuracy}) {
    return _run((c) async {
      await c.postGsUplink(
        content,
        sender: sender,
        locationLat: locationLat,
        locationLon: locationLon,
        locationAccuracy: locationAccuracy,
      );
      return true;
    });
  }

  static Future<List<GSMessage>> getGSMessages() {
    return _run((c) async {
      final list = await c.getGsMessages();
      return list.map(GSMessage.fromShared).toList();
    });
  }

  // --- announcements (file 05 task 5.3: the REAL endpoints) -----------------------

  static Future<List<shared.Announcement>> getAnnouncements() {
    return _run((c) => c.getAnnouncements());
  }

  // --- node health (file 05 task 5.3 optional strip) ------------------------------

  static Future<shared.NodeHealth> getHealth() {
    return _run((c) => c.getHealth());
  }
}
