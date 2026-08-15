import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_comment.dart';
import 'package:college_project_app/features/reports/data/models/report_detail.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/reports/data/reports_repository.dart';
import 'package:college_project_app/features/staff/data/staff_reports_repository.dart';
import 'package:college_project_app/features/staff/staff_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Report _report({ReportStatus status = ReportStatus.pending}) => Report(
      id: 'r-1',
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

ReportDetail _detail({ReportStatus status = ReportStatus.pending, bool assigned = false}) =>
    ReportDetail(
      report: _report(status: status),
      comments: const [],
      evidence: const [],
      activity: const [],
      activeAssigneeId: assigned ? 'staff-1' : null,
    );

/// Shared mutable server state so a status transition persists across the
/// staff-repository update and the subsequent detail reload.
class _ServerState {
  _ServerState(this.status, {this.assigned = false});

  ReportStatus status;
  bool assigned;
}

class _FakeReportsRepository extends ReportsRepository {
  _FakeReportsRepository(this.state)
      : super(
          client: SupabaseClient('http://localhost', 'anon-key'),
          currentUserId: 'staff-1',
        );

  final _ServerState state;
  int fetchCalls = 0;
  final List<String> commentLog = [];

  @override
  Future<ReportDetail> fetchDetail(String reportId) async {
    fetchCalls++;
    return _detail(status: state.status, assigned: state.assigned);
  }

  @override
  Future<ReportComment> addComment(String reportId, String message) async {
    commentLog.add(message);
    return ReportComment(
      id: 'c-1',
      reportId: reportId,
      authorId: 'staff-1',
      message: message,
      createdAt: DateTime(2026, 8, 15),
      isMine: true,
    );
  }
}

class _FakeStaffRepository extends StaffReportsRepository {
  _FakeStaffRepository(this.state)
      : super(client: SupabaseClient('http://localhost', 'anon-key'));

  final _ServerState state;
  bool accepted = true;
  ReportStatus? lastStatus;
  String? lastReportId;
  int calls = 0;

  @override
  Future<bool> updateStatus({
    required String reportId,
    required ReportStatus newStatus,
  }) async {
    calls++;
    lastReportId = reportId;
    lastStatus = newStatus;
    if (!accepted) return false;
    state.status = newStatus;
    return true;
  }
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  StaffDetailController build(
    _ServerState state, {
    _FakeReportsRepository? repo,
    _FakeStaffRepository? staff,
  }) =>
      StaffDetailController(
        repository: repo ?? _FakeReportsRepository(state),
        staffRepository: staff ?? _FakeStaffRepository(state),
        reportId: 'r-1',
      );

  group('StaffDetailController', () {
    test('loads the detail and reports assignment state', () async {
      final state = _ServerState(ReportStatus.pending, assigned: true);
      final controller = build(state);
      await settle();

      expect(controller.status, StaffDetailStatus.ready);
      expect(controller.report, isNotNull);
      expect(controller.isAssigned, isTrue);
    });

    group('availableTransitions', () {
      test('pending without assignment offers review and reject only', () async {
        final controller = build(_ServerState(ReportStatus.pending));
        await settle();

        expect(controller.availableTransitions, [ReportStatus.underReview, ReportStatus.rejected]);
      });

      test('pending with assignment also offers in progress', () async {
        final controller = build(
          _ServerState(ReportStatus.pending, assigned: true),
        );
        await settle();

        expect(controller.availableTransitions, [
          ReportStatus.underReview,
          ReportStatus.inProgress,
          ReportStatus.rejected,
        ]);
      });

      test('under review without assignment offers reject only', () async {
        final controller = build(_ServerState(ReportStatus.underReview));
        await settle();

        expect(controller.availableTransitions, [ReportStatus.rejected]);
      });

      test('in progress offers resolve and reject', () async {
        final controller = build(
          _ServerState(ReportStatus.inProgress, assigned: true),
        );
        await settle();

        expect(controller.availableTransitions, [ReportStatus.resolved, ReportStatus.rejected]);
      });

      test('resolved and rejected offer nothing to an HOD', () async {
        for (final status in [ReportStatus.resolved, ReportStatus.rejected]) {
          final controller = build(_ServerState(status));
          await settle();

          expect(controller.availableTransitions, isEmpty, reason: 'for $status');
        }
      });
    });

    group('changeStatus', () {
      test('applies an offered transition and reloads the detail', () async {
        final state = _ServerState(ReportStatus.pending);
        final repo = _FakeReportsRepository(state);
        final staff = _FakeStaffRepository(state);
        final controller = build(state, repo: repo, staff: staff);
        await settle();

        final accepted = await controller.changeStatus(ReportStatus.underReview);

        expect(accepted, isTrue);
        expect(staff.lastReportId, 'r-1');
        expect(staff.lastStatus, ReportStatus.underReview);
        expect(repo.fetchCalls, 2);
        expect(controller.report!.status, ReportStatus.underReview);
      });

      test('refuses a transition that is not offered (no assignment)', () async {
        final state = _ServerState(ReportStatus.pending);
        final staff = _FakeStaffRepository(state);
        final controller = build(state, staff: staff);
        await settle();

        final accepted = await controller.changeStatus(ReportStatus.inProgress);

        expect(accepted, isFalse);
        expect(staff.calls, 0);
      });

      test('returns false when the database rejects the transition', () async {
        final state = _ServerState(ReportStatus.pending);
        final staff = _FakeStaffRepository(state)..accepted = false;
        final controller = build(state, staff: staff);
        await settle();

        final accepted = await controller.changeStatus(ReportStatus.underReview);

        expect(accepted, isFalse);
        expect(controller.report!.status, ReportStatus.pending);
      });
    });

    group('reject', () {
      test('records a reason comment before the transition', () async {
        final state = _ServerState(ReportStatus.pending);
        final repo = _FakeReportsRepository(state);
        final staff = _FakeStaffRepository(state);
        final controller = build(state, repo: repo, staff: staff);
        await settle();

        final accepted = await controller.reject(reason: 'Duplicate of another report.');

        expect(accepted, isTrue);
        expect(repo.commentLog, ['Duplicate of another report.']);
        expect(staff.lastStatus, ReportStatus.rejected);
      });

      test('rejects without a reason comment when none given', () async {
        final state = _ServerState(ReportStatus.pending);
        final repo = _FakeReportsRepository(state);
        final staff = _FakeStaffRepository(state);
        final controller = build(state, repo: repo, staff: staff);
        await settle();

        await controller.reject(reason: '   ');

        expect(repo.commentLog, isEmpty);
        expect(staff.lastStatus, ReportStatus.rejected);
      });
    });

    test('addComment appends the comment to the detail', () async {
      final controller = build(_ServerState(ReportStatus.pending));
      await settle();

      await controller.addComment('Investigating.');

      expect(controller.detail!.comments, hasLength(1));
      expect(controller.detail!.comments.first.message, 'Investigating.');
    });
  });
}
