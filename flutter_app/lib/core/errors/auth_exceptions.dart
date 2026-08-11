/// Typed login failures mapped from the linways-login Edge Function responses.
enum LoginFailureKind {
  invalidCredentials,
  rateLimited,
  invalidRequest,
  serviceUnavailable,
  provisioningFailed,
  networkError,
  unexpected,
}

class LoginException implements Exception {
  const LoginException(this.kind, {this.message, this.retryAfterSeconds});

  final LoginFailureKind kind;

  /// Optional server-provided detail. Never contains credentials or tokens.
  final String? message;

  /// Seconds to wait before retrying (rate-limit responses only).
  final int? retryAfterSeconds;

  String get userFacingMessage => switch (kind) {
        LoginFailureKind.invalidCredentials =>
          'Invalid username or password. Please try again.',
        LoginFailureKind.rateLimited =>
          message ?? 'Too many attempts. Please wait a few minutes and try again.',
        LoginFailureKind.invalidRequest =>
          'Please check your username and password and try again.',
        LoginFailureKind.serviceUnavailable =>
          'The login service is temporarily unavailable. Please try again in a moment.',
        LoginFailureKind.provisioningFailed =>
          'Account setup failed. Please try again.',
        LoginFailureKind.networkError =>
          'No internet connection. Check your connection and try again.',
        LoginFailureKind.unexpected =>
          'Something went wrong. Please try again.',
      };
}
