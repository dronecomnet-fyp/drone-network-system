enum ApiErrorType {
  /// No usable credentials at all (no session token, no break-glass key).
  authFailed,

  /// 401: token invalid or expired; a fresh PIN login fixes it (file 05
  /// task 5.1: distinguish expired vs revoked when the backend says so).
  sessionExpired,

  /// 401 with a revoked credential: HQ has revoked this person. Logging in
  /// again with the same PIN will NOT help until HQ re-issues.
  revoked,

  /// 403: you ARE properly logged in, but this action is not for your role.
  /// Deliberately NOT a credential failure: treating it as one logged a
  /// rescuer out of the whole app for opening an HQ-only screen (bench
  /// finding 2026-07-14).
  notPermitted,

  rateLimited,
  serviceUnavailable,
  serverError,
  networkError,

  /// TLS handshake rejected: the node's certificate does not chain to the
  /// loaded fleet CA (possible evil twin) or no CA is loaded (file 09 F1).
  pinningFailed,

  timeout,
  badRequest,
  unknown,
}

class ApiException implements Exception {
  final ApiErrorType type;
  final int? statusCode;
  final String message;

  const ApiException({
    required this.type,
    required this.message,
    this.statusCode,
  });

  /// Any credential-shaped failure that should route the user to login.
  bool get isCredentialFailure =>
      type == ApiErrorType.authFailed ||
      type == ApiErrorType.sessionExpired ||
      type == ApiErrorType.revoked;

  @override
  String toString() {
    if (statusCode == null) {
      return message;
    }
    return '$message (HTTP $statusCode)';
  }
}
