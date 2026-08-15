import 'dart:convert';

import 'package:college_project_app/features/analytics/data/analytics_overview.dart';
import 'package:college_project_app/features/analytics/data/analytics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient clientWith(Future<http.Response> Function(http.Request) handler) {
  final mock = MockClient((request) async {
    final response = await handler(request);
    return http.Response(
      response.body,
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  });
  return SupabaseClient(
    'http://localhost:54321',
    'test-anon-key',
    httpClient: mock,
  );
}

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {
      'content-type': 'application/json',
    });

const overviewRow = {
  'total_reports': 4,
  'open_reports': 3,
  'by_status': {'pending': 2, 'in_progress': 1, 'resolved': 1},
  'by_category': {'Academic': 3, 'Infrastructure': 1},
  'by_priority': {'high': 3, 'medium': 1},
  'resolved_avg_days': 2.5,
};

void main() {
  group('AnalyticsOverview.fromJson', () {
    test('parses the RPC result', () {
      final overview = AnalyticsOverview.fromJson(overviewRow);

      expect(overview.totalReports, 4);
      expect(overview.openReports, 3);
      expect(overview.byStatus, {'pending': 2, 'in_progress': 1, 'resolved': 1});
      expect(overview.byCategory, {'Academic': 3, 'Infrastructure': 1});
      expect(overview.byPriority, {'high': 3, 'medium': 1});
      expect(overview.resolvedAvgDays, 2.5);
    });

    test('defaults missing counts to zero and avg to null', () {
      final overview = AnalyticsOverview.fromJson(const {
        'total_reports': 0,
        'open_reports': 0,
        'by_status': null,
        'by_category': null,
        'by_priority': null,
        'resolved_avg_days': null,
      });

      expect(overview.totalReports, 0);
      expect(overview.byStatus, isEmpty);
      expect(overview.resolvedAvgDays, isNull);
    });
  });

  group('AnalyticsRepository.fetchOverview', () {
    test('calls the rpc and parses the single row', () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/rpc/analytics_overview') {
          return jsonResponse([overviewRow]);
        }
        return jsonResponse([], 404);
      });

      final repository = AnalyticsRepository(client: client);
      final overview = await repository.fetchOverview();

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/rest/v1/rpc/analytics_overview');
      expect(overview.totalReports, 4);
    });

    test('throws when the rpc returns no rows', () async {
      final client = clientWith((request) async => jsonResponse([]));

      final repository = AnalyticsRepository(client: client);
      expect(repository.fetchOverview(), throwsStateError);
    });
  });
}