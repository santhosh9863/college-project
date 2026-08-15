import 'package:college_project_app/features/reports/data/categories_repository.dart';
import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_category.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/reports/data/reports_repository.dart';
import 'package:college_project_app/features/reports/reports_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Report _report({String id = 'r-1', ReportStatus status = ReportStatus.pending}) =>
    Report(
      id: id,
      title: 'Broken projector',
      description: 'Room 12.',
      status: status,
      priority: ReportPriority.high,
      reporterId: 'user-b',
      categoryId: 'cat-1',
      categoryName: 'Academic',
      communityId: 'community-1',
      supportCount: 0,
      isMine: false,
      isSupported: false,
      createdAt: DateTime(2026, 8, 15),
      updatedAt: DateTime(2026, 8, 15),
    );

class _FakeCategoriesRepository extends CategoriesRepository {
  _FakeCategoriesRepository({this.fail = false})
      : super(client: SupabaseClient('http://localhost', 'anon-key'));

  bool fail;
  int calls = 0;

  @override
  Future<List<ReportCategory>> fetchAll() async {
    calls++;
    if (fail) throw Exception('categories down');
    return const [
      ReportCategory(id: 'cat-1', name: 'Academic'),
      ReportCategory(id: 'cat-2', name: 'Facilities'),
    ];
  }
}

class _FakeReportsRepository extends ReportsRepository {
  _FakeReportsRepository({this.feed = const [], this.fail = false})
      : super(
          client: SupabaseClient('http://localhost', 'anon-key'),
          currentUserId: 'user-a',
        );

  List<Report> feed;
  bool fail;
  int calls = 0;
  String? lastStatusFilter;
  String? lastCategoryId;
  String? lastPriority;
  String lastSearch = '';
  bool? lastMineOnly;

  @override
  Future<List<Report>> fetchFeed({
    String statusFilter = 'all',
    String? categoryId,
    String? priority,
    String search = '',
    bool mineOnly = false,
  }) async {
    calls++;
    lastStatusFilter = statusFilter;
    lastCategoryId = categoryId;
    lastPriority = priority;
    lastSearch = search;
    lastMineOnly = mineOnly;
    if (fail) throw Exception('feed down');
    return feed;
  }
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('ReportsController', () {
    test('loads feed and categories on construction', () async {
      final repo = _FakeReportsRepository(feed: [_report()]);
      final categories = _FakeCategoriesRepository();
      final controller = ReportsController(
        repository: repo,
        categoriesRepository: categories,
      );
      await settle();

      expect(controller.status, ReportsStatus.ready);
      expect(controller.reports, hasLength(1));
      expect(controller.categories, hasLength(2));
      expect(repo.calls, 1);
    });

    test('empty feed shows ready with no reports', () async {
      final controller = ReportsController(
        repository: _FakeReportsRepository(),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await settle();

      expect(controller.status, ReportsStatus.ready);
      expect(controller.reports, isEmpty);
    });

    test('repo failure moves to error state and keeps the error', () async {
      final controller = ReportsController(
        repository: _FakeReportsRepository(fail: true),
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await settle();

      expect(controller.status, ReportsStatus.error);
      expect(controller.error, isA<Exception>());
    });

    test('categories failure is isolated from the feed', () async {
      final controller = ReportsController(
        repository: _FakeReportsRepository(feed: [_report()]),
        categoriesRepository: _FakeCategoriesRepository(fail: true),
      );
      await settle();

      expect(controller.status, ReportsStatus.ready);
      expect(controller.categoriesFailed, isTrue);
      expect(controller.categories, isEmpty);

      final categories = _FakeCategoriesRepository();
      final controller2 = ReportsController(
        repository: _FakeReportsRepository(),
        categoriesRepository: categories,
      );
      await settle();
      expect(controller2.categories, hasLength(2));
    });

    test('retryCategories recovers after a failure', () async {
      final categories = _FakeCategoriesRepository(fail: true);
      final controller = ReportsController(
        repository: _FakeReportsRepository(),
        categoriesRepository: categories,
      );
      await settle();
      expect(controller.categoriesFailed, isTrue);

      categories.fail = false;
      await controller.retryCategories();
      expect(controller.categoriesFailed, isFalse);
      expect(controller.categories, hasLength(2));
    });

    test('filters trigger reloads and propagate to the repository', () async {
      final repo = _FakeReportsRepository(feed: [_report()]);
      final controller = ReportsController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await settle();

      controller.setStatusFilter('in_progress');
      await settle();
      expect(repo.lastStatusFilter, 'in_progress');

      controller.setCategoryFilter('cat-2');
      await settle();
      expect(repo.lastCategoryId, 'cat-2');

      controller.setPriorityFilter('critical');
      await settle();
      expect(repo.lastPriority, 'critical');

      controller.setSearch('laptop');
      await settle();
      expect(repo.lastSearch, 'laptop');

      controller.setMineOnly(true);
      await settle();
      expect(repo.lastMineOnly, isTrue);

      expect(repo.calls, 6);
    });

    test('setting the same filter value does not reload', () async {
      final repo = _FakeReportsRepository(feed: [_report()]);
      final controller = ReportsController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await settle();
      expect(repo.calls, 1);

      controller.setStatusFilter('all');
      await settle();
      expect(repo.calls, 1);

      controller.setMineOnly(false);
      await settle();
      expect(repo.calls, 1);
    });

    test('clearFilters resets all filters', () async {
      final repo = _FakeReportsRepository(feed: [_report()]);
      final controller = ReportsController(
        repository: repo,
        categoriesRepository: _FakeCategoriesRepository(),
      );
      await settle();

      controller.setStatusFilter('resolved');
      controller.setCategoryFilter('cat-1');
      controller.setPriorityFilter('low');
      controller.setSearch('x');
      controller.setMineOnly(true);
      await settle();

      controller.clearFilters();
      await settle();

      expect(repo.lastStatusFilter, 'all');
      expect(repo.lastCategoryId, isNull);
      expect(repo.lastPriority, isNull);
      expect(repo.lastSearch, isEmpty);
      expect(repo.lastMineOnly, isFalse);
    });
  });
}
