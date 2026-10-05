import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Debug-only. Records why a 200 response was unusable. Key names and error
  /// types are logged; values are not, because a 200 body carries the session
  /// tokens this client is required to treat as secret.
  void _logParseFailure(Object error) {
    assert(() {
      debugPrint('ApiClient: 200 response failed to parse: '
          '${error.runtimeType}: $error');
      return true;
    }());
  }

  /// Debug-only. Records an HTTP status the client has no mapping for, which is
  /// what surfaces as the generic "unexpected" login error. Only the status and
  /// the top-level keys are logged so no token or cookie value can leak.
  void _logUnmappedStatus(http.Response response) {
    assert(() {
      Object? keys;
      try {
        final decoded = jsonDecode(response.body);
        keys = decoded is Map ? decoded.keys.toList() : decoded.runtimeType;
      } catch (_) {
        keys = 'non-JSON body';
      }
      debugPrint('ApiClient: unmapped status ${response.statusCode} '
          'from $_baseUrl; body keys: $keys');
      return true;
    }());
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
      } catch (error) {
        _logParseFailure(error);
      }
      _logUnmappedStatus(response);
      throw const LoginException(LoginFailureKind.unexpected);
    }

    final errorCode = body?['error'] as String?;
    final message = body?['message'] as String?;

    // 54X are Supabase platform states, not responses from the function: 540 is
    // "project paused", 544 an API gateway timeout. No amount of retrying helps,
    // so these are reported distinctly instead of collapsing into `unexpected`.
    if (response.statusCode >= 540 && response.statusCode < 550) {
      throw const LoginException(LoginFailureKind.projectUnavailable);
    }

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
        _logUnmappedStatus(response);
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
