import 'dart:convert';

import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/staff/data/staff_reports_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Builds a SupabaseClient whose HTTP layer is fully mocked (mirrors the
/// reports repository test harness).
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

const queueRow = {
  'id': 'report-1',
  'title': 'Broken projector',
  'description': 'Projector in room 12 is broken.',
  'status': 'pending',
  'priority': 'medium',
  'category_id': 'cat-1',
  'categories': {'name': 'Academic'},
  'reporter_id': 'user-a',
  'community_id': 'community-1',
  'report_supports': [
    {'count': 3},
  ],
  'created_at': '2026-08-15T10:00:00.000Z',
  'updated_at': '2026-08-15T11:00:00.000Z',
};

void main() {
  group('fetchQueue', () {
    test('parses queue rows and applies the support flag', () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/report_supports') {
          return jsonResponse([
            {'report_id': 'report-1'},
          ]);
        }
        if (request.url.path == '/rest/v1/reports') {
          return jsonResponse([queueRow]);
        }
        return jsonResponse([], 404);
      });

      final repository = StaffReportsRepository(client: client, currentUserId: 'user-a');
      final reports = await repository.fetchQueue();

      expect(reports, hasLength(1));
      expect(reports.first.id, 'report-1');
      expect(reports.first.supportCount, 3);
      expect(reports.first.isSupported, isTrue);

      final feedRequest = requests.firstWhere(
        (request) => request.url.path == '/rest/v1/reports',
      );
      final select =
          feedRequest.url.queryParameters['select'] ?? '';
      expect(select, contains('categories(name)'));
      expect(select, contains('report_supports(count)'));
    });

    test('applies the status filter and title search as query params', () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/report_supports') {
          return jsonResponse([]);
        }
        if (request.url.path == '/rest/v1/reports') {
          return jsonResponse([queueRow]);
        }
        return jsonResponse([], 404);
      });

      final repository = StaffReportsRepository(client: client, currentUserId: 'user-a');
      await repository.fetchQueue(statusFilter: 'in_progress', search: 'projector');

      final feedRequest = requests.firstWhere(
        (request) => request.url.path == '/rest/v1/reports',
      );
      final params = feedRequest.url.queryParameters;
      expect(params['status'], 'eq.in_progress');
      expect(params['title'], 'ilike.%projector%');
      expect(params['order'], 'created_at.desc.nullslast');
      expect(params['limit'], '50');
    });
  });

  group('updateStatus', () {
    test('PATCHes the new status and returns true when a row comes back', () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        if (request.method == 'PATCH' && request.url.path == '/rest/v1/reports') {
          return jsonResponse([
            {'id': 'report-1'},
          ]);
        }
        return jsonResponse([], 404);
      });

      final repository = StaffReportsRepository(client: client);
      final accepted = await repository.updateStatus(
        reportId: 'report-1',
        newStatus: ReportStatus.underReview,
      );

      expect(accepted, isTrue);
      final patch = requests.single;
      expect(patch.method, 'PATCH');
      final body = jsonDecode(patch.body) as Map<String, dynamic>;
      expect(body['status'], 'under_review');
      expect(body.containsKey('updated_at'), isTrue);
    });

    test('returns false when RLS rejects the transition (no row)', () async {
      final client = clientWith((request) async {
        return jsonResponse([]);
      });

      final repository = StaffReportsRepository(client: client);
      final accepted = await repository.updateStatus(
        reportId: 'report-1',
        newStatus: ReportStatus.underReview,
      );
      expect(accepted, isFalse);
    });
  });
}
