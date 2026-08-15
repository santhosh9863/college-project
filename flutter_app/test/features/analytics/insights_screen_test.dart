import 'package:college_project_app/features/analytics/analytics_controller.dart';
import 'package:college_project_app/features/analytics/data/analytics_overview.dart';
import 'package:college_project_app/features/analytics/data/analytics_repository.dart';
import 'package:college_project_app/features/analytics/insights_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAnalyticsRepository extends AnalyticsRepository {
  _FakeAnalyticsRepository({this.fail = false, this.empty = false})
      : super(
          client: SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: AuthClientOptions(autoRefreshToken: false),
          ),
        );

  final bool fail;
  final bool empty;

  @override
  Future<AnalyticsOverview> fetchOverview() async {
    if (fail) throw Exception('rpc failed');
    if (empty) {
      return const AnalyticsOverview(
        totalReports: 0,
        openReports: 0,
        byStatus: {},
        byCategory: {},
        byPriority: {},
      );
    }
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
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  testWidgets('renders summary tiles and breakdowns', (tester) async {
    final controller = AnalyticsController(
      repository: _FakeAnalyticsRepository(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InsightsScreen(controller: controller),
      ),
    );
    await settle(tester);

    expect(find.text('Total reports'), findsOneWidget);
    expect(find.text('4'), findsWidgets);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Avg. days to resolve'), findsOneWidget);
    expect(find.text('2.5'), findsOneWidget);
    expect(find.text('By status'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
    expect(find.text('By priority'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('Academic'), findsOneWidget);
  });

  testWidgets('shows the empty state when nothing is visible', (tester) async {
    final controller = AnalyticsController(
      repository: _FakeAnalyticsRepository(empty: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InsightsScreen(controller: controller),
      ),
    );
    await settle(tester);

    expect(find.text('No report data to show yet.'), findsOneWidget);
  });

  testWidgets('shows the error state with retry', (tester) async {
    final controller = AnalyticsController(
      repository: _FakeAnalyticsRepository(fail: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: InsightsScreen(controller: controller),
      ),
    );
    await settle(tester);

    expect(find.text('Could not load insights.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}