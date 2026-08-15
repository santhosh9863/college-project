import 'dart:convert';
import 'dart:io';

import 'package:college_project_app/features/reports/data/reports_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Builds a SupabaseClient whose HTTP layer is fully mocked. The response
/// wrapper re-attaches [http.Request.request] because postgrest dereferences
/// it when parsing responses (MockClient leaves it null otherwise).
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

const feedRow = {
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
  group('fetchFeed', () {
    test('parses rows with support counts and my-support flags', () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/report_supports') {
          return jsonResponse([
            {'report_id': 'report-1'},
          ]);
        }
        if (request.url.path == '/rest/v1/reports') {
          return jsonResponse([feedRow]);
        }
        return jsonResponse([], 404);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      final reports = await repository.fetchFeed();

      expect(reports, hasLength(1));
      expect(reports.first.id, 'report-1');
      expect(reports.first.supportCount, 3);
      expect(reports.first.isMine, isTrue);
      expect(reports.first.isSupported, isTrue);

      final feedRequest = requests.first;
      final select =
          feedRequest.url.queryParameters['select'] ?? '';
      expect(select, contains('categories(name)'));
      expect(select, contains('report_supports(count)'));
    });

    test('applies status, category, priority, search and mine filters', () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/report_supports') {
          return jsonResponse([]);
        }
        if (request.url.path == '/rest/v1/reports') {
          return jsonResponse([feedRow]);
        }
        return jsonResponse([], 404);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      await repository.fetchFeed(
        statusFilter: 'under_review',
        categoryId: 'cat-2',
        priority: 'critical',
        search: '  projector  ',
        mineOnly: true,
      );

      final feedRequest = requests.first;
      final params = feedRequest.url.queryParameters;
      expect(params['status'], 'eq.under_review');
      expect(params['category_id'], 'eq.cat-2');
      expect(params['priority'], 'eq.critical');
      expect(params['title'], 'ilike.%projector%');
      expect(params['reporter_id'], 'eq.user-a');
      expect(params['order'], 'created_at.desc.nullslast');
      expect(params['limit'], '50');
    });

    test('no filters are applied when defaults are used', () async {
      final requests = <http.Request>[];
      final client = clientWith((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/report_supports') {
          return jsonResponse([]);
        }
        if (request.url.path == '/rest/v1/reports') {
          return jsonResponse([feedRow]);
        }
        return jsonResponse([], 404);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      await repository.fetchFeed();

      final params = requests.first.url.queryParameters;
      expect(params.containsKey('status'), isFalse);
      expect(params.containsKey('category_id'), isFalse);
      expect(params.containsKey('priority'), isFalse);
      expect(params.containsKey('title'), isFalse);
      expect(params.containsKey('reporter_id'), isFalse);
    });

    test('propagates API errors', () async {
      final client = clientWith((request) async {
        return http.Response(
          jsonEncode({
            'code': '42501',
            'message': 'new row violates row-level security policy',
          }),
          400,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      expect(repository.fetchFeed(), throwsA(isA<PostgrestException>()));
    });
  });

  group('fetchDetail', () {
    final detailRow = {
      ...feedRow,
      'report_comments': [
        {
          'id': 'c-1',
          'author_id': 'user-b',
          'message': 'Same issue here.',
          'created_at': '2026-08-15T10:05:00.000Z',
        },
      ],
      'evidence_files': [
        {
          'id': 'e-1',
          'report_id': 'report-1',
          'file_url': 'evidence/report-1/1_photo.png',
          'file_type': 'image/png',
          'uploaded_by': 'user-a',
          'created_at': '2026-08-15T10:01:00.000Z',
        },
      ],
      'report_activity': [
        {
          'id': 'a-1',
          'actor_id': 'user-a',
          'activity_type': 'created',
          'metadata': {'report_type': 'community'},
          'created_at': '2026-08-15T10:00:00.000Z',
        },
      ],
      'report_assignments': [
        {'assigned_to': 'staff-1', 'active': true},
        {'assigned_to': 'staff-0', 'active': false},
      ],
    };

    test('parses the full detail', () async {
      final client = clientWith((request) async {
        if (request.url.path == '/rest/v1/report_supports') {
          return jsonResponse([]);
        }
        if (request.url.path == '/rest/v1/reports') {
          return jsonResponse([detailRow]);
        }
        return jsonResponse([], 404);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      final detail = await repository.fetchDetail('report-1');

      expect(detail.report.title, 'Broken projector');
      expect(detail.comments, hasLength(1));
      expect(detail.comments.first.isMine, isFalse);
      expect(detail.evidence, hasLength(1));
      expect(detail.evidence.first.isMine, isTrue);
      expect(detail.activity, hasLength(1));
      expect(detail.activity.first.displayMessage, 'Report created');
      expect(detail.activeAssigneeId, 'staff-1');
      expect(detail.report.isSupported, isFalse);
    });

    test('throws ReportNotFoundException when not visible', () async {
      final client = clientWith((request) async {
        if (request.url.path == '/rest/v1/report_supports') {
          return jsonResponse([]);
        }
        return jsonResponse([]);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      expect(
        repository.fetchDetail('invisible'),
        throwsA(isA<ReportNotFoundException>()),
      );
    });
  });

  group('createReport', () {
    test('sends the approved pending community payload', () async {
      http.Request? captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({'id': 'new-report-1'});
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      final id = await repository.createReport(
        title: '  Broken projector  ',
        description: '  Room 12 projector.  ',
        categoryId: 'cat-1',
        priority: 'high',
        departmentId: 'dept-1',
        communityId: 'community-1',
        semester: 5,
        section: 'C',
      );

      expect(id, 'new-report-1');
      expect(captured!.url.path, '/rest/v1/reports');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['report_type'], 'community');
      expect(body['status'], 'pending');
      expect(body['title'], 'Broken projector');
      expect(body['description'], 'Room 12 projector.');
      expect(body['category_id'], 'cat-1');
      expect(body['priority'], 'high');
      expect(body['department_id'], 'dept-1');
      expect(body['community_id'], 'community-1');
      expect(body['semester'], 5);
      expect(body['section'], 'C');
      expect(body['reporter_id'], 'user-a');
    });
  });

  group('support', () {
    test('addSupport inserts the caller as supporter', () async {
      http.Request? captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse([]);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      await repository.addSupport('report-1');

      expect(captured!.method, 'POST');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['report_id'], 'report-1');
      expect(body['supporter_id'], 'user-a');
    });

    test('withdrawSupport deletes only the own row', () async {
      http.Request? captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse([]);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      await repository.withdrawSupport('report-1');

      expect(captured!.method, 'DELETE');
      expect(captured!.url.queryParameters['report_id'], 'eq.report-1');
      expect(captured!.url.queryParameters['supporter_id'], 'eq.user-a');
    });
  });

  group('comments', () {
    test('addComment inserts own comment and returns it', () async {
      http.Request? captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse({
          'id': 'c-9',
          'report_id': 'report-1',
          'author_id': 'user-a',
          'message': 'Please fix soon.',
          'created_at': '2026-08-15T12:00:00.000Z',
        });
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      final comment = await repository.addComment('report-1', '  Please fix soon.  ');

      expect(captured!.method, 'POST');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body['report_id'], 'report-1');
      expect(body['author_id'], 'user-a');
      expect(body['message'], 'Please fix soon.');
      expect(comment.id, 'c-9');
      expect(comment.isMine, isTrue);
    });

    test('deleteComment deletes by id', () async {
      http.Request? captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse([]);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      await repository.deleteComment('c-9');

      expect(captured!.method, 'DELETE');
      expect(captured!.url.queryParameters['id'], 'eq.c-9');
    });
  });

  group('cancelReport', () {
    test('soft-deletes own report and returns true', () async {
      http.Request? captured;
      final client = clientWith((request) async {
        captured = request;
        return jsonResponse([
          {'id': 'report-1'},
        ]);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      final cancelled = await repository.cancelReport('report-1');

      expect(cancelled, isTrue);
      expect(captured!.method, 'PATCH');
      final body = jsonDecode(captured!.body) as Map<String, dynamic>;
      expect(body.containsKey('deleted_at'), isTrue);
      expect(body.containsKey('updated_at'), isTrue);
      expect(body.containsKey('status'), isFalse);
      expect(captured!.url.queryParameters['id'], 'eq.report-1');
      expect(captured!.url.queryParameters['reporter_id'], 'eq.user-a');
    });

    test('returns false when the database rejects the update', () async {
      final client = clientWith((request) async => jsonResponse([]));

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      expect(await repository.cancelReport('report-1'), isFalse);
    });
  });

  group('fetchMyCommunityId', () {
    test('returns the caller community id', () async {
      final client = clientWith(
        (request) async => jsonResponse([
          {'id': 'community-1'},
        ]),
      );

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      expect(await repository.fetchMyCommunityId(), 'community-1');
    });

    test('returns null when no community is assigned', () async {
      final client = clientWith((request) async => jsonResponse([]));

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      expect(await repository.fetchMyCommunityId(), isNull);
    });
  });

  group('evidence', () {
    test('uploads to the private bucket and records metadata', () async {
      final dir = await Directory.systemTemp.createTemp('evidence_test');
      final file = File('${dir.path}/photo.png')..writeAsBytesSync([1, 2, 3]);
      final requests = <http.Request>[];

      final client = clientWith((request) async {
        requests.add(request);
        if (request.url.path.contains('/storage/v1/object/evidence/')) {
          return jsonResponse({'Key': request.url.pathSegments.join('/')});
        }
        if (request.url.path == '/rest/v1/evidence_files') {
          return jsonResponse({
            'id': 'e-1',
            'report_id': 'report-1',
            'file_url': 'evidence/report-1/1_photo.png',
            'file_type': 'image/png',
            'uploaded_by': 'user-a',
            'created_at': '2026-08-15T10:00:00.000Z',
          });
        }
        return jsonResponse([], 404);
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      final evidence = await repository.uploadEvidence(
        reportId: 'report-1',
        filePath: file.path,
        contentType: 'image/png',
      );

      expect(evidence.fileType, 'image/png');
      expect(evidence.isMine, isTrue);
      expect(evidence.fileUrl, startsWith('evidence/report-1/'));
      expect(requests.first.url.path, contains('/storage/v1/object/evidence/'));
      expect(requests.last.url.path, '/rest/v1/evidence_files');

      await dir.delete(recursive: true);
    });

    test('signedEvidenceUrl returns a signed URL string', () async {
      final client = clientWith((request) async {
        expect(request.url.path, contains('/storage/v1/object/sign/evidence/'));
        return jsonResponse({
          'signedURL': '/storage/v1/object/sign/evidence/path/1_photo.png?token=t',
        });
      });

      final repository = ReportsRepository(
        client: client,
        currentUserId: 'user-a',
      );
      final url = await repository.signedEvidenceUrl('evidence/path/1_photo.png');
      expect(url, startsWith('http://localhost:54321'));
      expect(url, contains('token=t'));
    });
  });

  group('mimeTypeFor', () {
    test('resolves supported types', () {
      expect(ReportsRepository.mimeTypeFor('scan.pdf'), 'application/pdf');
      expect(ReportsRepository.mimeTypeFor('pic.png'), 'image/png');
    });
  });
}
