import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_notification.dart';

/// Notifications data access. RLS restricts reads to the caller's own rows
/// (`notifications_select_own`); writes are limited to the `read` column.
class NotificationsRepository {
  NotificationsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static const int _limit = 50;

  /// PostgrestException is thrown on API failures and propagates to the caller.
  Future<List<AppNotification>> fetchRecent() async {
    final rows = await _client
        .from('notifications')
        .select('id, title, body, type, reference_id, read, created_at')
        .eq('user_id', _requireUserId())
        .order('created_at', ascending: false)
        .limit(_limit);

    return rows.map(AppNotification.fromJson).toList();
  }

  Future<void> markRead(String id) async {
    await _client
        .from('notifications')
        .update({'read': true}).eq('id', id);
  }

  Future<void> markAllRead() async {
    await _client
        .from('notifications')
        .update({'read': true})
        .eq('user_id', _requireUserId())
        .eq('read', false);
  }

  String _requireUserId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('No authenticated user');
    }
    return userId;
  }
}
