import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/staff/data/staff_reports_repository.dart';
import 'package:college_project_app/features/staff/staff_queue_controller.dart';
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

class _FakeStaffReportsRepository extends StaffReportsRepository {
  _FakeStaffReportsRepository({this.queue = const [], this.fail = false})
      : super(client: SupabaseClient('http://localhost', 'anon-key'));

  List<Report> queue;
  bool fail;
  int calls = 0;
  String? lastStatusFilter;
  String lastSearch = '';

  @override
  Future<List<Report>> fetchQueue({
    String statusFilter = 'all',
    String search = '',
  }) async {
    calls++;
    lastStatusFilter = statusFilter;
    lastSearch = search;
    if (fail) throw Exception('queue down');
    return queue;
  }
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('StaffQueueController', () {
    test('loads the department queue on construction', () async {
      final repo = _FakeStaffReportsRepository(queue: [_report()]);
      final controller = StaffQueueController(repository: repo);
      await settle();

      expect(controller.status, StaffQueueStatus.ready);
      expect(controller.reports, hasLength(1));
      expect(repo.calls, 1);
    });

    test('empty queue is ready with no reports', () async {
      final controller = StaffQueueController(
        repository: _FakeStaffReportsRepository(),
      );
      await settle();

      expect(controller.status, StaffQueueStatus.ready);
      expect(controller.reports, isEmpty);
      expect(controller.hasActiveFilters, isFalse);
    });

    test('repo failure moves to error state and keeps the error', () async {
      final controller = StaffQueueController(
        repository: _FakeStaffReportsRepository(fail: true),
      );
      await settle();

      expect(controller.status, StaffQueueStatus.error);
      expect(controller.error, isA<Exception>());
    });

    test('status filter triggers a reload with the filter', () async {
      final repo = _FakeStaffReportsRepository(queue: [_report()]);
      final controller = StaffQueueController(repository: repo);
      await settle();

      controller.setStatusFilter('in_progress');
      await settle();

      expect(repo.calls, 2);
      expect(repo.lastStatusFilter, 'in_progress');
      expect(controller.hasActiveFilters, isTrue);
    });

    test('search filter triggers a reload and clear resets filters', () async {
      final repo = _FakeStaffReportsRepository(queue: [_report()]);
      final controller = StaffQueueController(repository: repo);
      await settle();

      controller.setSearch('projector');
      await settle();
      expect(repo.lastSearch, 'projector');
      expect(controller.hasActiveFilters, isTrue);

      controller.clearFilters();
      await settle();
      expect(repo.lastStatusFilter, 'all');
      expect(repo.lastSearch, '');
      expect(controller.hasActiveFilters, isFalse);
    });
  });
}
