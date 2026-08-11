import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data/models/login_result.dart';
import '../config/app_config.dart';
import '../errors/auth_exceptions.dart';

/// HTTP client for the deployed linways-login Edge Function.
///
/// The Linways username/password are used in-memory only: they are sent in the
/// request body and never logged, stored, or exposed by this client.
class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _http = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? AppConfig.linwaysLoginUrl;

  final http.Client _http;
  final String _baseUrl;

  Future<LoginResult> login({
    required String username,
    required String password,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(_baseUrl),
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(AppConfig.loginTimeout);
    } on TimeoutException {
      throw const LoginException(LoginFailureKind.serviceUnavailable);
    } catch (_) {
      throw const LoginException(LoginFailureKind.networkError);
    }

    return _parse(response);
  }

  LoginResult _parse(http.Response response) {
    Map<String, dynamic>? body;
    try {
      final decoded = jsonDecode(response.body);
      body = decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      body = null;
    }

    if (response.statusCode == 200) {
      try {
        final result = body == null ? null : LoginResult.fromJson(body);
        if (result != null) return result;
      } catch (_) {
        // Fall through to the unexpected-error mapping below.
      }
      throw const LoginException(LoginFailureKind.unexpected);
    }

    final errorCode = body?['error'] as String?;
    final message = body?['message'] as String?;
    switch (response.statusCode) {
      case 400:
        throw const LoginException(LoginFailureKind.invalidRequest);
      case 401:
        throw const LoginException(LoginFailureKind.invalidCredentials);
      case 429:
        final retryAfter = body?['retry_after_seconds'];
        throw LoginException(
          LoginFailureKind.rateLimited,
          message: message,
          retryAfterSeconds: retryAfter is int ? retryAfter : null,
        );
      case 502:
        throw const LoginException(LoginFailureKind.serviceUnavailable);
      case 500:
        throw const LoginException(LoginFailureKind.provisioningFailed);
      default:
        // Fallback: honor a well-known error code even with an odd status.
        throw LoginException(
          switch (errorCode) {
            'invalid_credentials' => LoginFailureKind.invalidCredentials,
            'rate_limited' => LoginFailureKind.rateLimited,
            'invalid_request' => LoginFailureKind.invalidRequest,
            'linways_unavailable' => LoginFailureKind.serviceUnavailable,
            'profile_unavailable' => LoginFailureKind.serviceUnavailable,
            'provisioning_failed' => LoginFailureKind.provisioningFailed,
            _ => LoginFailureKind.unexpected,
          },
          message: message,
        );
    }
  }
}
