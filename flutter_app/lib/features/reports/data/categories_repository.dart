import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/report_category.dart';

/// Categories data access. Reference data — read-only (RLS grants SELECT to
/// all authenticated users; no client writes).
class CategoriesRepository {
  CategoriesRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// PostgrestException is thrown on API failures and propagates to the caller.
  Future<List<ReportCategory>> fetchAll() async {
    final rows = await _client
        .from('categories')
        .select('id, name')
        .order('name', ascending: true);

    return rows.map(ReportCategory.fromJson).toList();
  }
}
