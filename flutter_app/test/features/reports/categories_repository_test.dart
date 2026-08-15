import 'dart:convert';

import 'package:college_project_app/features/reports/data/categories_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('CategoriesRepository', () {
    test('fetches and parses categories ordered by name', () async {
      http.Request? captured;
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        httpClient: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode([
              {'id': 'cat-1', 'name': 'Academic'},
              {'id': 'cat-2', 'name': 'Facilities'},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );

      final repository = CategoriesRepository(client: client);
      final categories = await repository.fetchAll();

      expect(categories, hasLength(2));
      expect(categories.first.name, 'Academic');
      expect(captured!.url.path, '/rest/v1/categories');
      expect(captured!.url.queryParameters['order'], 'name.asc.nullslast');
    });

    test('propagates API errors', () {
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-anon-key',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode({'code': '42501', 'message': 'denied'}),
            400,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );

      final repository = CategoriesRepository(client: client);
      expect(repository.fetchAll(), throwsA(isA<PostgrestException>()));
    });
  });
}
