import 'package:supabase_flutter/supabase_flutter.dart';

import 'report.dart';

/// Reports data access. Reads are automatically community-scoped by RLS
/// (`report_visible_to_caller`): a student sees reports from their active
/// community plus their own historical reports — never other communities.
class ReportsRepository {
  ReportsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int _limit = 50;

  /// PostgrestException is thrown on API failures and propagates to the caller.
  Future<List<Report>> fetchCommunityReports() async {
    final rows = await _client
        .from('reports')
        .select('id, title, description, status, priority, created_at, categories(name)')
        .order('created_at', ascending: false)
        .limit(_limit);

    return rows.map(Report.fromJson).toList();
  }
}
