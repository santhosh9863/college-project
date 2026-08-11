import 'dart:convert';

import 'package:college_project_app/features/attendance/data/linways_attendance_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _cookies = 'AUTH_SESSION=eyJtoken.abc; refresh_token=cookie-secret';

Map<String, dynamic> _successBody() => {
      'success': true,
      'data': <String, dynamic>{
        'totalHours': 120,
        'attendedHours': 107,
        'totalPresent': 107,
        'attendancePercentage': 89.11,
        'isHourWiseEnabled': true,
      },
    };

LinwaysAttendanceRepository _repository(
  http.Client client, {
  String? cookies = _cookies,
}) =>
    LinwaysAttendanceRepository(
      httpClient: client,
      readCookies: () async => cookies,
    );

void main() {
  group('LinwaysAttendanceRepository.fetchSummary', () {
    test('GETs the confirmed endpoint with Cookie and Bearer auth', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(_successBody()),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final summary = await _repository(client).fetchSummary();

      expect(
        captured.url.toString(),
        'https://sfcv4.linways.com/academics/api/v1/student/get-my-attendance-summary',
      );
      expect(captured.method, 'GET');
      expect(captured.headers['Cookie'], _cookies);
      expect(captured.headers['Authorization'], 'Bearer eyJtoken.abc');
      expect(captured.headers['Accept'], 'application/json');
      expect(captured.headers['Referer'], 'https://sfcv4.linways.com/academics/');

      expect(summary.attendancePercentage, 89.11);
      expect(summary.totalHours, 120);
      expect(summary.attendedHours, 107);
      expect(summary.isHourWiseEnabled, isTrue);
    });

    test('omits the Bearer header when no AUTH_SESSION cookie is stored', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode(_successBody()), 200);
      });

      await _repository(client, cookies: 'refresh_token=cookie-secret').fetchSummary();

      expect(captured.headers.containsKey('Authorization'), isFalse);
      expect(captured.headers['Cookie'], 'refresh_token=cookie-secret');
    });

    test('parses a doubly-nested data payload', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'data': {'attendancePercentage': 75.5, 'isHourWiseEnabled': false},
            },
          }),
          200,
        ),
      );

      final summary = await _repository(client).fetchSummary();
      expect(summary.attendancePercentage, 75.5);
      expect(summary.totalHours, 0);
    });

    test('maps 401 to sessionExpired', () async {
      final client = MockClient((_) async => http.Response('unauthorized', 401));

      await expectLater(
        _repository(client).fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>().having(
            (e) => e.kind,
            'kind',
            LinwaysAttendanceFailureKind.sessionExpired,
          ),
        ),
      );
    });

    test('maps 403 to sessionExpired', () async {
      final client = MockClient((_) async => http.Response('forbidden', 403));

      await expectLater(
        _repository(client).fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>().having(
            (e) => e.kind,
            'kind',
            LinwaysAttendanceFailureKind.sessionExpired,
          ),
        ),
      );
    });

    test('maps server errors to network', () async {
      final client = MockClient((_) async => http.Response('boom', 503));

      await expectLater(
        _repository(client).fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>()
              .having((e) => e.kind, 'kind', LinwaysAttendanceFailureKind.network),
        ),
      );
    });

    test('maps transport failures to network', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('connection refused'),
      );

      await expectLater(
        _repository(client).fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>()
              .having((e) => e.kind, 'kind', LinwaysAttendanceFailureKind.network),
        ),
      );
    });

    test('maps a non-JSON 200 body to unexpected', () async {
      final client = MockClient((_) async => http.Response('not json', 200));

      await expectLater(
        _repository(client).fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>()
              .having((e) => e.kind, 'kind', LinwaysAttendanceFailureKind.unexpected),
        ),
      );
    });

    test('maps a body without data to unexpected', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'success': true, 'data': null}), 200),
      );

      await expectLater(
        _repository(client).fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>()
              .having((e) => e.kind, 'kind', LinwaysAttendanceFailureKind.unexpected),
        ),
      );
    });

    test('fails with noSession when no Linways cookies are stored', () async {
      final client = MockClient((_) async => http.Response('unexpected', 200));

      await expectLater(
        _repository(client, cookies: null).fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>()
              .having((e) => e.kind, 'kind', LinwaysAttendanceFailureKind.noSession),
        ),
      );
    });

    test('fails with noSession for blank cookies', () async {
      final client = MockClient((_) async => http.Response('unexpected', 200));

      await expectLater(
        _repository(client, cookies: '   ').fetchSummary(),
        throwsA(
          isA<LinwaysAttendanceException>()
              .having((e) => e.kind, 'kind', LinwaysAttendanceFailureKind.noSession),
        ),
      );
    });
  });
}
