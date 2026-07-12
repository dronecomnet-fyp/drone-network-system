/// AuthProvider (file 05 task 5.1): PIN login session lifecycle.
///
/// The session token is minted by whichever node the phone is joined to
/// and verifies OFFLINE on any node (HMAC, fleet-wide key), so a rescuer
/// can log in under drone A and keep working under drone B. Revocation
/// arrives at DTN sync speed; a 403 means re-issued credentials are
/// needed, not a retry.
library;

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
