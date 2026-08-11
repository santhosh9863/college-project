import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../core/security/secure_store.dart';
import 'attendance_summary.dart';

enum LinwaysAttendanceFailureKind {
  /// No Linways session cookies on this device.
  noSession,

  /// Linways rejected the stored session (401); re-login is required.
  sessionExpired,

  /// Transport or server failure; the last known value may still be shown.
  network,

  /// Response could not be parsed.
  unexpected,
}

class LinwaysAttendanceException implements Exception {
  const LinwaysAttendanceException(this.kind, {this.message});

  final LinwaysAttendanceFailureKind kind;
  final String? message;

  @override
  String toString() => 'LinwaysAttendanceException($kind${message == null ? '' : ': $message'})';
}

/// Direct Linways attendance client (split-token architecture, option C):
/// the device holds the Linways session (FlutterSecureStorage) and calls the
/// confirmed summary endpoint directly — the same pattern the college's PULSE
/// app uses in production. Attendance is never stored in Supabase.
class LinwaysAttendanceRepository {
  LinwaysAttendanceRepository({
    http.Client? httpClient,
    SecureStore? secureStore,
    Future<String?> Function()? readCookies,
  })  : _client = httpClient ?? http.Client(),
        _readCookies = readCookies ?? (secureStore ?? SecureStore()).readLinwaysCookies;

  final http.Client _client;
  final Future<String?> Function() _readCookies;

  static const String _summaryPath = '/academics/api/v1/student/get-my-attendance-summary';

  Future<AttendanceSummary> fetchSummary() async {
    final cookies = await _readCookies();
    if (cookies == null || cookies.trim().isEmpty) {
      throw const LinwaysAttendanceException(LinwaysAttendanceFailureKind.noSession);
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Cookie': cookies,
      'Referer': '${AppConfig.linwaysBaseUrl}/academics/',
    };
    final authSession = _extractAuthSession(cookies);
    if (authSession != null) {
      // PULSE pattern: the AUTH_SESSION cookie value is itself a JWT and is
      // sent as the bearer credential alongside the Cookie header.
      headers['Authorization'] = 'Bearer $authSession';
    }

    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse('${AppConfig.linwaysBaseUrl}$_summaryPath'),
            headers: headers,
          )
          .timeout(AppConfig.linwaysAttendanceTimeout);
    } on TimeoutException {
      throw const LinwaysAttendanceException(LinwaysAttendanceFailureKind.network);
    } on http.ClientException {
      throw const LinwaysAttendanceException(LinwaysAttendanceFailureKind.network);
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const LinwaysAttendanceException(LinwaysAttendanceFailureKind.sessionExpired);
    }
    if (response.statusCode != 200) {
      throw const LinwaysAttendanceException(LinwaysAttendanceFailureKind.network);
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('attendance payload is not a JSON object');
      }
      // Defensive unwrap: { success, data: {...} } with the payload possibly
      // nested one level deeper.
      var payload = decoded['data'];
      if (payload is Map<String, dynamic> && payload['data'] is Map<String, dynamic>) {
        payload = payload['data'];
      }
      if (payload is! Map<String, dynamic>) {
        throw const FormatException('attendance data missing');
      }
      return AttendanceSummary.fromJson(payload);
    } catch (_) {
      throw const LinwaysAttendanceException(LinwaysAttendanceFailureKind.unexpected);
    }
  }

  /// Extracts the `AUTH_SESSION` JWT from a cookie header string.
  static String? _extractAuthSession(String cookies) {
    final match = RegExp(r'(?:^|;\s*)AUTH_SESSION=([^;]+)').firstMatch(cookies);
    return match?.group(1);
  }
}
