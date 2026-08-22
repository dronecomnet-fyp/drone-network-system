/// AuthProvider (file 05 task 5.1): PIN login session lifecycle.
///
/// The session token is minted by whichever node the phone is joined to
/// and verifies OFFLINE on any node (HMAC, fleet-wide key), so a rescuer
/// can log in under drone A and keep working under drone B. Revocation
/// arrives at DTN sync speed; a 403 means re-issued credentials are
/// needed, not a retry.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:rescue_mesh_shared/rescue_mesh_shared.dart' as shared;

import '../config/api_config.dart';
import '../models/api_error_model.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  shared.AuthSession? _session;
  bool _loaded = false;
  bool _hasBreakGlassKey = false;

  /// Set when the API layer force-logged-us-out (expired/revoked), so the
  /// login screen can explain why.
  String? lastLogoutReason;

  shared.AuthSession? get session => _session;
  bool get isLoaded => _loaded;
  bool get isLoggedIn => _session != null && !_session!.isExpired;

  /// Break-glass/admin mode (file 05 task 5.1): a static key saved in
  /// Settings lets the app work without PIN login, clearly labeled as the
  /// recovery path. Refreshed after Settings saves.
  bool get breakGlassAccepted => _hasBreakGlassKey;
  String get personnelId => _session?.personnelId ?? '';
  String get displayName =>
      _session == null ? '' : '${_session!.personnelId} (${_session!.name})';

  Future<void> load() async {
    _session = await SessionStore.load();
    _hasBreakGlassKey = (await ApiConfigStore.load()).hasApiKey;
    _loaded = true;
    notifyListeners();
  }

  Future<void> refreshBreakGlass() async {
    _hasBreakGlassKey = (await ApiConfigStore.load()).hasApiKey;
    notifyListeners();
  }

  /// Returns null on success, else a user-facing error message.
  Future<String?> login(String personnelId, String pin) async {
    try {
      final session = await APIService.login(personnelId, pin);
      _session = session;
      lastLogoutReason = null;
      await SessionStore.save(session);
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  /// Sign in from a scanned QR: no typing at all.
  ///
  /// Two calls, invisible to the rescuer. First the signed record is handed
  /// to whichever drone they are standing next to, so a node that has never
  /// met the issuing one still knows who they are. Then an ordinary PIN
  /// login using the PIN carried in the code.
  ///
  /// Enrolment failing is not fatal on its own: the node may already know
  /// them, in which case login will simply work. Only a failed LOGIN is
  /// reported, because that is the part the rescuer cares about.
  Future<String?> signInWithCode(String scanned) async {
    final decoded = decodeSigninCode(scanned);
    if (decoded == null) {
      return 'Could not read the sign-in code. Make sure you are scanning '
             'the QR from the personnel screen on the HQ laptop (not a '
             'different QR). If the code looks right, ask HQ to issue new '
             'credentials.';
    }
    try {
      await APIService.enrol(decoded.enrolment);
    } on ApiException catch (e) {
      // 400 Bad Request usually means "already known" or invalid record, but if
      // it's a network, timeout, or TLS error (pinningFailed), we must report
      // it because the subsequent login will also definitely fail for the same
      // reason. 401/403 shouldn't happen for public /enrol.
      if (e.type == ApiErrorType.pinningFailed ||
          e.type == ApiErrorType.networkError ||
          e.type == ApiErrorType.timeout) {
        return 'Network error before sign-in: ${e.message}';
      }
      // Otherwise, node might be older (404) or it already knows this enrolment,
      // so try the login anyway.
    } catch (_) {
      // Unforeseen error, try login anyway.
    }
    return login(decoded.personnelId, decoded.pin);
  }

  Future<void> logout() async {
    _session = null;
    lastLogoutReason = null;
    await SessionStore.clear();
    notifyListeners();
  }

  /// Called by the data layer when the backend rejects our credentials
  /// (401 expired / 403 revoked): clear the stored token and surface the
  /// reason on the login screen (file 05 task 5.1).
  Future<void> handleCredentialFailure(ApiException error) async {
    if (!error.isCredentialFailure) {
      return;
    }
    _session = null;
    lastLogoutReason = error.message;
    await SessionStore.clear();
    notifyListeners();
  }
}

/// The three fields inside a scanned sign-in code.
class SigninCode {
  const SigninCode(
      {required this.personnelId, required this.pin, required this.enrolment});
  final String personnelId;
  final String pin;
  final String enrolment;
}

/// Decode what the GCC put in the QR, or null if this is some other QR.
///
/// Kept small and pure so it can be unit tested without a camera, and so a
/// stray barcode from a shipping label produces a clear message rather than
/// a crash.
SigninCode? decodeSigninCode(String scanned) {
  try {
    final text = scanned.trim();
    if (text.isEmpty) return null;

    // "Z" marks a deflated payload. Codes are compressed because an
    // uncompressed one needed a QR so dense that no phone could read it
    // (see the note in backend/api.py). The uncompressed form is still
    // accepted so a code printed before that change keeps working.
    final String raw;
    if (text.startsWith('Z')) {
      // Strip the "Z" prefix and any trailing whitespace a QR reader might add.
      var b64 = text.substring(1).replaceAll(RegExp(r'\s'), '');
      final bytes = base64Url.decode(base64Url.normalize(b64));
      raw = utf8.decode(zlib.decode(bytes));
    } else {
      var b64 = text.replaceAll(RegExp(r'\s'), '');
      raw = utf8.decode(base64Url.decode(base64Url.normalize(b64)));
    }

    final map = jsonDecode(raw);
    if (map is! Map) return null;
    final id = (map['i'] ?? '') as String;
    final pin = (map['p'] ?? '') as String;

    // The record travels as an OBJECT now, and the phone re-encodes it
    // into the blob POST /enrol expects. The server verifies the
    // signature over named fields, so re-encoding is safe: key order
    // does not affect verification.
    final e = map['e'];
    final String enrolment;
    if (e is Map) {
      enrolment = base64Url.encode(utf8.encode(jsonEncode(e)));
    } else if (e is String) {
      enrolment = e; // legacy code, already a blob
    } else {
      return null;
    }

    if (id.isEmpty || pin.isEmpty || enrolment.isEmpty) return null;
    return SigninCode(personnelId: id, pin: pin, enrolment: enrolment);
  } catch (e, st) {
    debugPrint('decodeSigninCode failed: $e\n$st');
    return null;
  }
}
