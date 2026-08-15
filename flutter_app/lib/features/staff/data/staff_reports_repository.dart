import 'package:supabase_flutter/supabase_flutter.dart';

import '../../reports/data/models/report.dart';
import '../../reports/data/models/report_status.dart';

/// Staff (HOD) report operations. The database is the authority: RLS returns
/// exactly the D1 department-scoped routed queue on read, and `can_update_report`
/// gates the status transitions on write. No client-side filtering or
/// permission logic lives here.
class StaffReportsRepository {
  StaffReportsRepository({SupabaseClient? client, String? currentUserId})
      : _client = client ?? Supabase.instance.client,
        _currentUserId = currentUserId;

  final SupabaseClient _client;
  final String? _currentUserId;

  static const int _limit = 50;
  static const String _queueSelect =
      'id, title, description, status, priority, category_id, reporter_id, '
      'community_id, created_at, updated_at, categories(name), report_supports(count)';

  /// Department-routed queue (RLS `reports_select_visible` + D1 scope).
  Future<List<Report>> fetchQueue({
    String statusFilter = 'all',
    String search = '',
  }) async {
    var query = _client.from('reports').select(_queueSelect);

    if (statusFilter != 'all') {
      query = query.eq('status', statusFilter);
    }
    if (search.trim().isNotEmpty) {
      query = query.ilike('title', '%${search.trim()}%');
    }

    final rows = await query.order('created_at', ascending: false).limit(_limit);
    final reports = rows
        .map((row) => Report.fromJson(row, currentUserId: _userId))
        .toList();
    final supportedIds = await _fetchMySupportedIds();
    return reports
        .map((report) => report.copyWith(isSupported: supportedIds.contains(report.id)))
        .toList();
  }

  Future<Set<String>> _fetchMySupportedIds() async {
    final rows =
        await _client.from('report_supports').select('report_id').eq('supporter_id', _userId);
    return rows.map((row) => row['report_id'] as String).toSet();
  }

  /// Applies a lifecycle status transition. RLS (`reports_update_gated` +
  /// `can_transition_status`) is the enforcement; returns whether the update
  /// was accepted.
  Future<bool> updateStatus({
    required String reportId,
    required ReportStatus newStatus,
  }) async {
    final rows = await _client
        .from('reports')
        .update({
          'status': newStatus.apiValue,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', reportId)
        .select('id');
    return rows.isNotEmpty;
  }

  String get _userId {
    final current = _currentUserId;
    if (current != null) return current;
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user');
    }
    return user.id;
  }
}
