import 'dart:convert';

import 'package:college_project_app/core/errors/auth_exceptions.dart';
import 'package:college_project_app/core/network/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _successBody() => {
      'success': true,
      'data': <String, dynamic>{
        'supabase_session': {
          'access_token': 'at-test',
          'refresh_token': 'rt-test',
        },
        'profile': {
          'id': '1c324517-81f9-4aa1-8856-fe1a826e726c',
          'full_name': 'SANTHOSH KRISHNA R',
          'email': 'santhoshkrishna.r67@gmail.com',
          'role': 'student',
          'semester': 5,
          'section': 'C',
          'student_id': 'U18IW24S0166',
        },
        'community': {
          'course_code': 'BCA',
          'batch_year': 2024,
          'semester': 'S5',
          'section': 'C',
        },
        'linways_session_cookies': 'AUTH_SESSION=eyJtest; refresh_token=cookietest',
      },
    };

void main() {
  group('ApiClient.login', () {
    test('POSTs username/password and parses the documented response', () async {
      late http.Request captured;
      final mock = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(_successBody()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        httpClient: mock,
        baseUrl: 'https://example.test/linways-login',
      );
      final result = await client.login(
        username: 'U18IW24S0166',
        password: 'test-password',
      );

      expect(captured.method, 'POST');
      expect(captured.url.toString(), 'https://example.test/linways-login');
      expect(captured.headers['Content-Type'], contains('application/json'));
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['username'], 'U18IW24S0166');
      expect(body['password'], 'test-password');

      expect(result.accessToken, 'at-test');
      expect(result.refreshToken, 'rt-test');
      expect(result.profile.fullName, 'SANTHOSH KRISHNA R');
      expect(result.profile.role, 'student');
      expect(result.profile.studentId, 'U18IW24S0166');
      expect(result.community?.displayName, 'BCA 2024 S5 C');
      expect(result.linwaysSessionCookies, 'AUTH_SESSION=eyJtest; refresh_token=cookietest');
    });

    test('parses a null community as community_pending', () async {
      final body = _successBody();
      (body['data'] as Map<String, dynamic>)['community'] = null;
      final mock = MockClient((_) async => http.Response(jsonEncode(body), 200));

      final result = await ApiClient(httpClient: mock).login(
        username: 'u',
        password: 'p',
      );

      expect(result.community, isNull);
      expect(result.profile.isValid, isTrue);
    });

    test('maps 401 to invalidCredentials', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'invalid_credentials', 'message': 'Invalid username or password'}),
          401,
        ),
      );

      await expectLater(
        ApiClient(httpClient: mock).login(username: 'u', password: 'p'),
        throwsA(
          isA<LoginException>()
              .having((e) => e.kind, 'kind', LoginFailureKind.invalidCredentials),
        ),
      );
    });

    test('maps 429 to rateLimited and preserves retry_after_seconds', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': 'rate_limited',
            'message': 'Too many login attempts.',
            'retry_after_seconds': 900,
          }),
          429,
        ),
      );

      await expectLater(
        ApiClient(httpClient: mock).login(username: 'u', password: 'p'),
        throwsA(
          isA<LoginException>()
              .having((e) => e.kind, 'kind', LoginFailureKind.rateLimited)
              .having((e) => e.retryAfterSeconds, 'retryAfterSeconds', 900),
        ),
      );
    });

    test('maps 502 to serviceUnavailable', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'linways_unavailable'}),
          502,
        ),
      );

      await expectLater(
        ApiClient(httpClient: mock).login(username: 'u', password: 'p'),
        throwsA(
          isA<LoginException>()
              .having((e) => e.kind, 'kind', LoginFailureKind.serviceUnavailable),
        ),
      );
    });

    test('maps 500 to provisioningFailed', () async {
      final mock = MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'provisioning_failed'}),
          500,
        ),
      );

      await expectLater(
        ApiClient(httpClient: mock).login(username: 'u', password: 'p'),
        throwsA(
          isA<LoginException>()
              .having((e) => e.kind, 'kind', LoginFailureKind.provisioningFailed),
        ),
      );
    });

    test('maps transport failures to networkError', () async {
      final mock = MockClient(
        (_) async => throw http.ClientException('connection refused'),
      );

      await expectLater(
        ApiClient(httpClient: mock).login(username: 'u', password: 'p'),
        throwsA(
          isA<LoginException>()
              .having((e) => e.kind, 'kind', LoginFailureKind.networkError),
        ),
      );
    });

    test('maps a malformed 200 body to unexpected', () async {
      final mock = MockClient(
        (_) async => http.Response('{"success": true, "data": {}}', 200),
      );

      await expectLater(
        ApiClient(httpClient: mock).login(username: 'u', password: 'p'),
        throwsA(
          isA<LoginException>()
              .having((e) => e.kind, 'kind', LoginFailureKind.unexpected),
        ),
      );
    });

    test('maps a non-JSON 200 body to unexpected', () async {
      final mock = MockClient((_) async => http.Response('not json', 200));

      await expectLater(
        ApiClient(httpClient: mock).login(username: 'u', password: 'p'),
        throwsA(
          isA<LoginException>()
              .having((e) => e.kind, 'kind', LoginFailureKind.unexpected),
        ),
      );
    });
  });
}
