import 'package:college_project_app/data/models/profile.dart';
import 'package:college_project_app/features/reports/create_report_controller.dart';
import 'package:college_project_app/features/reports/create_report_screen.dart';
import 'package:college_project_app/features/reports/data/categories_repository.dart';
import 'package:college_project_app/features/reports/data/models/evidence_file.dart';
import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_category.dart';
import 'package:college_project_app/features/reports/data/models/report_comment.dart';
import 'package:college_project_app/features/reports/data/models/report_detail.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/reports/data/reports_repository.dart';
import 'package:college_project_app/features/reports/report_detail_controller.dart';
import 'package:college_project_app/features/reports/report_detail_screen.dart';
import 'package:college_project_app/features/reports/reports_controller.dart';
import 'package:college_project_app/features/reports/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Report _report({String id = 'r-1', bool mine = false, String status = 'pending'}) =>
    Report(
      id: id,
      title: 'Broken projector',
      description: 'Projector in room 12 is broken.',
      status: ReportStatus.fromApi(status),
      priority: ReportPriority.high,
      reporterId: mine ? 'user-a' : 'user-b',
      categoryId: 'cat-1',
      categoryName: 'Academic',
      communityId: 'community-1',
      supportCount: 2,
      isMine: mine,
      isSupported: false,
      createdAt: DateTime(2026, 8, 15),
      updatedAt: DateTime(2026, 8, 15),
    );

/// Test SupabaseClient: HTTP is never called and the gotrue auto-refresh
/// timer is disabled so widget tests finish without pending timers.
SupabaseClient _testClient() => SupabaseClient(
      'http://localhost',
      'anon-key',
      authOptions: AuthClientOptions(autoRefreshToken: false),
    );

class _FakeCategoriesRepository extends CategoriesRepository {
  _FakeCategoriesRepository() : super(client: _testClient());

  @override
  Future<List<ReportCategory>> fetchAll() async {
    return const [
      ReportCategory(id: 'cat-1', name: 'Academic'),
      ReportCategory(id: 'cat-2', name: 'Facilities'),
    ];
  }
}

class _FakeReportsRepository extends ReportsRepository {
  _FakeReportsRepository({this.feed = const [], this.mineDetail = false, this.failCreate = false})
      : super(client: _testClient(), currentUserId: 'user-a');

  final List<Report> feed;
  final bool mineDetail;
  final bool failCreate;

  @override
  Future<List<Report>> fetchFeed({
    String statusFilter = 'all',
    String? categoryId,
    String? priority,
    String search = '',
    bool mineOnly = false,
  }) async {
    return feed;
  }

  @override
  Future<String?> fetchMyCommunityId() async => 'community-1';

  @override
  Future<String> createReport({
    required String title,
    required String description,
    required String categoryId,
    required String priority,
    required String departmentId,
    required String communityId,
    int? semester,
    String? section,
  }) async {
    if (failCreate) throw Exception('create failed');
    return 'r-new';
  }

  @override
  Future<ReportDetail> fetchDetail(String reportId) async => ReportDetail(
        report: _report(mine: mineDetail),
        comments: [
          ReportComment(
            id: 'c-1',
            reportId: 'r-1',
            authorId: 'user-b',
            message: 'Same issue here.',
            createdAt: DateTime(2026, 8, 15),
          ),
        ],
        evidence: const [],
        activity: const [],
        activeAssigneeId: null,
      );

  @override
  Future<EvidenceFile> uploadEvidence({
    required String reportId,
    required String filePath,
    required String contentType,
  }) async {
    return EvidenceFile(
      id: 'e-1',
      reportId: reportId,
      fileUrl: 'evidence/$reportId/x.png',
      fileType: contentType,
      uploadedBy: 'user-a',
      createdAt: DateTime(2026, 8, 15),
    );
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ReportsScreen', () {
    testWidgets('renders report tiles with author and support labels',
        (tester) async {
      final controller = ReportsController(
        repository: _FakeReportsRepository(feed: [_report()]),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(ReportsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Broken projector'), findsOneWidget);
      expect(find.textContaining('Academic'), findsWidgets);
      expect(find.textContaining('Community member'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets);
      expect(find.text('New report'), findsOneWidget);
      expect(find.text('Search reports'), findsOneWidget);
    });

    testWidgets('renders the empty state without filters', (tester) async {
      final controller = ReportsController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(ReportsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('No reports yet from your community.'), findsOneWidget);
    });

    testWidgets('shows an empty state for filtered results', (tester) async {
      final controller = ReportsController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(ReportsScreen(controller: controller)));
      await tester.pumpAndSettle();

      controller.setPriorityFilter('critical');
      await tester.pumpAndSettle();

      expect(find.text('No reports match your filters.'), findsOneWidget);
      expect(find.text('Clear filters'), findsOneWidget);
    });

    testWidgets('clear filters restores the unfiltered empty state',
        (tester) async {
      final controller = ReportsController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(ReportsScreen(controller: controller)));
      await tester.pumpAndSettle();

      controller.setSearch('laptop');
      await tester.pumpAndSettle();
      expect(find.text('No reports match your filters.'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('No reports yet from your community.'), findsOneWidget);
    });

    testWidgets('filter bar does not overflow on narrow screens',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = ReportsController(
        repository: _FakeReportsRepository(feed: [_report()]),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(ReportsScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('My reports'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CreateReportScreen', () {
    testWidgets('shows the first validation message after a submit attempt',
        (tester) async {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(CreateReportScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Submit report'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Title'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Add a short title.'), findsOneWidget);
    });

    testWidgets('opens the category sheet and marks the chosen category',
        (tester) async {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(CreateReportScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a category').first);
      await tester.pumpAndSettle();

      expect(find.text('Academic'), findsOneWidget);
      expect(find.text('Facilities'), findsOneWidget);

      await tester.tap(find.text('Academic'));
      await tester.pumpAndSettle();

      expect(controller.categoryId, 'cat-1');
      expect(find.text('Academic'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('renders all priority options without wrapping', (tester) async {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await tester.pumpWidget(wrap(CreateReportScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Critical'),
        300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Low'), findsOneWidget);
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.text('Critical'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('surfaces the underlying submit failure in the error card',
        (tester) async {
      final controller = CreateReportController(
        repository: _FakeReportsRepository(failCreate: true),
        categoriesRepository: _FakeCategoriesRepository(),
        profile: const Profile(
          id: 'user-a',
          fullName: 'Test Student',
          email: 'student@college.example',
          role: 'student',
          semester: 5,
          section: 'C',
          studentId: 'S-2024-001',
          departmentId: 'dept-1',
        ),
      );
      await tester.pumpWidget(wrap(CreateReportScreen(controller: controller)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Broken projector');
      await tester.enterText(find.byType(TextField).at(1), 'Room 12.');
      await tester.tap(find.text('Choose a category').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Academic'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Medium'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Medium'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Submit report'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();

      expect(controller.lastSubmitError, isA<Exception>());
      expect(controller.error, contains('Details (debug)'));
      await tester.scrollUntilVisible(
        find.textContaining('Details (debug)'),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Details (debug)'), findsOneWidget);
      expect(find.textContaining('create failed'), findsOneWidget);
    });
  });

  group('ReportDetailScreen', () {
    testWidgets('renders header, description, comments and support sections',
        (tester) async {
      final controller = ReportDetailController(
        repository: _FakeReportsRepository(mineDetail: false),
        reportId: 'r-1',
      );
      await tester.pumpWidget(wrap(ReportDetailScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Broken projector'), findsOneWidget);
      expect(find.text('Projector in room 12 is broken.'), findsOneWidget);
      expect(find.text('Updates'), findsNothing);
      expect(find.text('Comments'), findsOneWidget);
      expect(find.text('Same issue here.'), findsOneWidget);
      expect(find.text('Support'), findsOneWidget);
      expect(find.text('2 community members support this'), findsOneWidget);
      expect(find.text('Add a comment'), findsOneWidget);
    });

    testWidgets('hides the support card for own reports', (tester) async {
      final repo = _FakeReportsRepository(mineDetail: true);
      final controller = ReportDetailController(
        repository: repo,
        reportId: 'r-1',
      );
      await tester.pumpWidget(wrap(ReportDetailScreen(controller: controller)));
      await tester.pumpAndSettle();

      expect(find.text('Support'), findsNothing);
      expect(find.text('Cancel my report'), findsOneWidget);
    });
  });
}



