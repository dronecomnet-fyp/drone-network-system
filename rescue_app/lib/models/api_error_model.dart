enum ApiErrorType {
  /// No usable credentials at all (no session token, no break-glass key).
  authFailed,

  /// 401: token invalid or expired; a fresh PIN login fixes it (file 05
  /// task 5.1: distinguish expired vs revoked when the backend says so).
  sessionExpired,

  /// 403: credentials revoked or insufficient role; logging in again with
  /// the same PIN will NOT help until HQ re-issues.
  revoked,

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
