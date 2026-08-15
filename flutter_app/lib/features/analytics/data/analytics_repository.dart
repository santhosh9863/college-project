import 'package:supabase_flutter/supabase_flutter.dart';

import 'analytics_overview.dart';

/// Analytics data access. The server-side `analytics_overview` RPC (D6)
/// aggregates over exactly the rows the caller may see, so no client-side
/// filtering is needed (or possible) here.
class AnalyticsRepository {
  AnalyticsRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// PostgrestException is thrown on API failures and propagates to the caller.
  Future<AnalyticsOverview> fetchOverview() async {
    final rows = await _client.rpc('analytics_overview').select();
    if (rows.isEmpty) {
      throw StateError('analytics_overview returned no row');
    }
    return AnalyticsOverview.fromJson(rows.first);
  }
}