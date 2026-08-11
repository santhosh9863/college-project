import 'dart:convert';

import 'package:college_project_app/features/attendance/attendance_controller.dart';
import 'package:college_project_app/features/attendance/data/linways_attendance_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _CountingClient extends MockClient {
  _CountingClient(super.handler);

  int requestCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requestCount += 1;
    return super.send(request);
  }
}

_CountingClient _okClient() {
  return _CountingClient(
    (_) async => http.Response(
      jsonEncode({
        'success': true,
        'data': {
          'totalHours': 120,
          'attendedHours': 107,
          'totalPresent': 107,
          'attendancePercentage': 89.11,
          'isHourWiseEnabled': true,
        },
      }),
      200,
    ),
  );
}

_CountingClient _failingClient() {
  return _CountingClient((_) async => throw http.ClientException('down'));
}

AttendanceController _controller(_CountingClient client) => AttendanceController(
      repository: LinwaysAttendanceRepository(
        httpClient: client,
        readCookies: () async => 'AUTH_SESSION=eyJtoken.abc',
      ),
    );

void main() {
  group('AttendanceController cache behaviour', () {
    test('loads on construction and caches within the TTL', () async {
      final client = _okClient();
      final controller = _controller(client);
      await pumpEventQueue();

      expect(controller.status, AttendanceStatus.ready);
      expect(controller.summary?.attendancePercentage, 89.11);
      expect(controller.sessionExpired, isFalse);

      await controller.load();
      await controller.load();
      expect(client.requestCount, 1, reason: 'fresh cache must not refetch');
      controller.dispose();
    });

    test('refresh bypasses the cache', () async {
      final client = _okClient();
      final controller = _controller(client);
      await pumpEventQueue();

      await controller.refresh();
      expect(client.requestCount, 2);
      controller.dispose();
    });

    test('failure with no cached value -> unavailable', () async {
      final client = _failingClient();
      final controller = _controller(client);
      await pumpEventQueue();

      expect(controller.status, AttendanceStatus.unavailable);
      expect(controller.summary, isNull);
      expect(controller.sessionExpired, isFalse);
      controller.dispose();
    });

    test('failure with a cached value -> stale, last value retained', () async {
      var fail = false;
      final client = _CountingClient((_) async {
        if (fail) throw http.ClientException('down');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'totalHours': 120,
              'attendedHours': 107,
              'attendancePercentage': 89.11,
              'isHourWiseEnabled': true,
            },
          }),
          200,
        );
      });
      final controller = _controller(client);
      await pumpEventQueue();
      expect(controller.status, AttendanceStatus.ready);

      fail = true;
      await controller.refresh();

      expect(controller.status, AttendanceStatus.stale);
      expect(controller.summary?.attendancePercentage, 89.11,
          reason: 'last known value is retained');
      controller.dispose();
    });
  });

  group('AttendanceController session expiry', () {
    test('a 401 marks the session as expired', () async {
      final client = _CountingClient((_) async => http.Response('no', 401));
      final controller = _controller(client);
      await pumpEventQueue();

      expect(controller.status, AttendanceStatus.unavailable);
      expect(controller.sessionExpired, isTrue);
      controller.dispose();
    });

    test('recovery: a later successful refresh clears the expired flag', () async {
      var fail = true;
      final client = _CountingClient((_) async {
        if (fail) return http.Response('no', 401);
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {'attendancePercentage': 90, 'isHourWiseEnabled': false},
          }),
          200,
        );
      });
      final controller = _controller(client);
      await pumpEventQueue();
      expect(controller.sessionExpired, isTrue);

      fail = false;
      await controller.refresh();
      expect(controller.status, AttendanceStatus.ready);
      expect(controller.sessionExpired, isFalse);
      expect(controller.summary?.attendancePercentage, 90);
      controller.dispose();
    });
  });
}
