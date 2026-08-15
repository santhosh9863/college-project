import 'package:college_project_app/features/analytics/analytics_controller.dart';
import 'package:college_project_app/features/analytics/data/analytics_overview.dart';
import 'package:college_project_app/features/analytics/data/analytics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAnalyticsRepository extends AnalyticsRepository {
  _FakeAnalyticsRepository({this.fail = false})
      : super(
          client: SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final bool fail;
  int fetchCalls = 0;

  @override
  Future<AnalyticsOverview> fetchOverview() async {
    fetchCalls++;
    if (fail) throw Exception('rpc failed');
    return const AnalyticsOverview(
      totalReports: 4,
      openReports: 3,
      byStatus: {'pending': 2, 'in_progress': 1, 'resolved': 1},
      byCategory: {'Academic': 4},
      byPriority: {'high': 3, 'medium': 1},
      resolvedAvgDays: 2.5,
    );
  }
}

void main() {
  test('load exposes the overview in ready state', () async {
    final repo = _FakeAnalyticsRepository();
    final controller = AnalyticsController(repository: repo);
    await controller.load();

    expect(controller.status, AnalyticsStatus.ready);
    expect(controller.overview?.totalReports, 4);
    expect(controller.overview?.byStatus['pending'], 2);
  });

  test('load exposes errors with the error state', () async {
    final repo = _FakeAnalyticsRepository(fail: true);
    final controller = AnalyticsController(repository: repo);
    await controller.load();

    expect(controller.status, AnalyticsStatus.error);
    expect(controller.error, isNotNull);
    expect(controller.overview, isNull);
  });
}