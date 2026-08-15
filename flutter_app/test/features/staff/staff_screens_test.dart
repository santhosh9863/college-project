import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_detail.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/reports/data/reports_repository.dart';
import 'package:college_project_app/features/staff/data/assignable_staff.dart';
import 'package:college_project_app/features/staff/data/staff_reports_repository.dart';
import 'package:college_project_app/features/staff/staff_detail_controller.dart';
import 'package:college_project_app/features/staff/staff_detail_screen.dart';
import 'package:college_project_app/features/staff/staff_queue_controller.dart';
import 'package:college_project_app/features/staff/staff_queue_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Report _report({
  String id = 'r-1',
  String title = 'Broken projector',
  ReportStatus status = ReportStatus.pending,
}) =>
    Report(
      id: id,
      title: title,
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
  _FakeStaffReportsRepository({this.queue = const []})
      : super(
          client: SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: AuthClientOptions(autoRefreshToken: false),
          ),
        );

  List<Report> queue;

  @override
  Future<List<Report>> fetchQueue({
    String statusFilter = 'all',
    String search = '',
  }) async {
    if (statusFilter == 'pending') {
      return queue.where((r) => r.status == ReportStatus.pending).toList();
    }
    return queue;
  }

  @override
  Future<List<AssignableStaff>> listAssignableStaff() async => const [
        AssignableStaff(id: 'staff-1', fullName: 'Anu Sharma', role: 'technician'),
        AssignableStaff(
          id: 'staff-2',
          fullName: 'Ravi Menon',
          role: 'hod',
          departmentCode: 'GENERAL',
        ),
      ];

  @override
  Future<bool> assign({
    required String reportId,
    required String assigneeId,
  }) async =>
      true;
}

class _FakeReportsRepository extends ReportsRepository {
  _FakeReportsRepository({this.detail})
      : super(
          client: SupabaseClient(
            'http://localhost',
            'anon-key',
            authOptions: AuthClientOptions(autoRefreshToken: false),
          ),
          currentUserId: 'staff-1',
        );

  ReportDetail? detail;

  @override
  Future<ReportDetail> fetchDetail(String reportId) async =>
      detail ??
      ReportDetail(
        report: _report(),
        comments: const [],
        evidence: const [],
        activity: const [],
        activeAssigneeId: null,
      );
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('StaffQueueScreen', () {
    testWidgets('renders the department queue tiles', (tester) async {
      final controller = StaffQueueController(
        repository: _FakeStaffReportsRepository(
          queue: [
            _report(id: 'r-1', title: 'Broken projector', status: ReportStatus.pending),
            _report(id: 'r-2', title: 'Campus Wi-Fi down', status: ReportStatus.inProgress),
          ],
        ),
        detailRepository: _FakeReportsRepository(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StaffQueueScreen(controller: controller)),
        ),
      );
      await settle(tester);

      expect(find.text('Broken projector'), findsOneWidget);
      expect(find.text('Pending'), findsNWidgets(2));
      expect(find.text('In progress'), findsNWidgets(2));
      expect(find.text('Search department reports'), findsOneWidget);
    });

    testWidgets('shows the empty state when the queue has no reports', (tester) async {
      final controller = StaffQueueController(
        repository: _FakeStaffReportsRepository(),
        detailRepository: _FakeReportsRepository(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StaffQueueScreen(controller: controller)),
        ),
      );
      await settle(tester);

      expect(find.textContaining('No department reports right now'), findsOneWidget);
    });
  });

  group('StaffDetailScreen', () {
    testWidgets('offers review and reject for a pending unassigned report',
        (tester) async {
      final controller = StaffDetailController(
        repository: _FakeReportsRepository(),
        staffRepository: _FakeStaffReportsRepository(),
        reportId: 'r-1',
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffDetailScreen(controller: controller)),
      );
      await settle(tester);

      expect(find.text('Start review'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Mark in progress'), findsNothing);
      expect(find.text('Broken projector'), findsOneWidget);
    });

    testWidgets('offers in progress once a report is assigned', (tester) async {
      final controller = StaffDetailController(
        repository: _FakeReportsRepository(
          detail: ReportDetail(
            report: _report(),
            comments: const [],
            evidence: const [],
            activity: const [],
            activeAssigneeId: 'staff-2',
          ),
        ),
        staffRepository: _FakeStaffReportsRepository(),
        reportId: 'r-1',
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffDetailScreen(controller: controller)),
      );
      await settle(tester);

      expect(find.text('Mark in progress'), findsOneWidget);
      expect(find.text('Assigned to staff'), findsOneWidget);
    });

    testWidgets('offers resolve and reject for an in-progress report', (tester) async {
      final controller = StaffDetailController(
        repository: _FakeReportsRepository(
          detail: ReportDetail(
            report: _report(status: ReportStatus.inProgress),
            comments: const [],
            evidence: const [],
            activity: const [],
            activeAssigneeId: 'staff-2',
          ),
        ),
        staffRepository: _FakeStaffReportsRepository(),
        reportId: 'r-1',
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffDetailScreen(controller: controller)),
      );
      await settle(tester);

      expect(find.text('Mark resolved'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
      expect(find.text('Start review'), findsNothing);
    });

    testWidgets('hides the assignment card for the HOD panel', (tester) async {
      final controller = StaffDetailController(
        repository: _FakeReportsRepository(),
        staffRepository: _FakeStaffReportsRepository(),
        reportId: 'r-1',
        role: 'hod',
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffDetailScreen(controller: controller)),
      );
      await settle(tester);

      expect(find.text('Assignment'), findsNothing);
      expect(find.text('Assign'), findsNothing);
    });

    testWidgets('operations panel shows the assignment card and picker',
        (tester) async {
      final controller = StaffDetailController(
        repository: _FakeReportsRepository(),
        staffRepository: _FakeStaffReportsRepository(),
        reportId: 'r-1',
        role: 'operations',
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffDetailScreen(controller: controller)),
      );
      await settle(tester);

      expect(find.text('Assignment'), findsOneWidget);
      expect(find.text('Not assigned'), findsOneWidget);
      expect(find.text('Assign'), findsOneWidget);

      await tester.tap(find.text('Assign'));
      await settle(tester);

      expect(find.text('Assign to staff'), findsOneWidget);
      expect(find.text('Anu Sharma'), findsOneWidget);
      expect(find.text('Ravi Menon'), findsOneWidget);
      expect(find.textContaining('GENERAL'), findsOneWidget);
    });

    testWidgets('operations may reopen a resolved report once reassigned',
        (tester) async {
      final controller = StaffDetailController(
        repository: _FakeReportsRepository(
          detail: ReportDetail(
            report: _report(status: ReportStatus.resolved),
            comments: const [],
            evidence: const [],
            activity: const [],
            activeAssigneeId: 'staff-2',
          ),
        ),
        staffRepository: _FakeStaffReportsRepository(),
        reportId: 'r-1',
        role: 'operations',
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffDetailScreen(controller: controller)),
      );
      await settle(tester);

      expect(find.text('Reopen review'), findsOneWidget);
      expect(find.text('Reopen work'), findsOneWidget);
    });

    testWidgets('operations cannot reopen a resolved report without a new assignment',
        (tester) async {
      final controller = StaffDetailController(
        repository: _FakeReportsRepository(
          detail: ReportDetail(
            report: _report(status: ReportStatus.resolved),
            comments: const [],
            evidence: const [],
            activity: const [],
            activeAssigneeId: null,
          ),
        ),
        staffRepository: _FakeStaffReportsRepository(),
        reportId: 'r-1',
        role: 'operations',
      );
      await tester.pumpWidget(
        MaterialApp(home: StaffDetailScreen(controller: controller)),
      );
      await settle(tester);

      expect(find.text('Reopen review'), findsNothing);
      expect(find.text('Reopen work'), findsNothing);
      expect(find.text('Assign'), findsOneWidget);
    });
  });
}
