import 'package:college_project_app/features/reports/data/models/evidence_file.dart';
import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_activity_item.dart';
import 'package:college_project_app/features/reports/data/models/report_comment.dart';
import 'package:college_project_app/features/reports/data/models/report_detail.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:college_project_app/features/reports/data/reports_repository.dart';
import 'package:college_project_app/features/reports/report_detail_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Report _report({bool mine = false, int supportCount = 2}) => Report(
      id: 'r-1',
      title: 'Broken projector',
      description: 'Room 12.',
      status: ReportStatus.pending,
      priority: ReportPriority.high,
      reporterId: mine ? 'user-a' : 'user-b',
      categoryId: 'cat-1',
      categoryName: 'Academic',
      communityId: 'community-1',
      supportCount: supportCount,
      isMine: mine,
      isSupported: false,
      createdAt: DateTime(2026, 8, 15),
      updatedAt: DateTime(2026, 8, 15),
    );

ReportDetail _detail({Report? report}) => ReportDetail(
      report: report ?? _report(),
      comments: const [],
      evidence: const [],
      activity: [
        ReportActivityItem(
          id: 'a-1',
          reportId: 'r-1',
          activityType: 'created',
          actorId: 'user-a',
          metadata: const {},
          createdAt: DateTime(2026, 8, 15),
        ),
      ],
      activeAssigneeId: null,
    );

class _FakeReportsRepository extends ReportsRepository {
  _FakeReportsRepository({this.detail, this.failLoad = false})
      : super(
          client: SupabaseClient('http://localhost', 'anon-key'),
          currentUserId: 'user-a',
        );

  ReportDetail? detail;
  bool failLoad;
  bool supportFails = false;
  final List<String> supportLog = [];

  @override
  Future<ReportDetail> fetchDetail(String reportId) async {
    if (failLoad) throw ReportNotFoundException();
    return detail ?? _detail();
  }

  @override
  Future<void> addSupport(String reportId) async {
    supportLog.add('add:$reportId');
    if (supportFails) throw Exception('support failed');
  }

  @override
  Future<void> withdrawSupport(String reportId) async {
    supportLog.add('withdraw:$reportId');
    if (supportFails) throw Exception('support failed');
  }

  @override
  Future<ReportComment> addComment(String reportId, String message) async {
    return ReportComment(
      id: 'c-new',
      reportId: reportId,
      authorId: 'user-a',
      message: message,
      createdAt: DateTime(2026, 8, 15),
      isMine: true,
    );
  }

  @override
  Future<void> deleteComment(String commentId) async {}

  @override
  Future<bool> cancelReport(String reportId) async => true;

  @override
  Future<EvidenceFile> uploadEvidence({
    required String reportId,
    required String filePath,
    required String contentType,
  }) async {
    return EvidenceFile(
      id: 'e-new',
      reportId: reportId,
      fileUrl: 'evidence/$reportId/new.png',
      fileType: contentType,
      uploadedBy: 'user-a',
      createdAt: DateTime(2026, 8, 15),
    );
  }
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('ReportDetailController', () {
    test('loads the detail and exposes summary getters', () async {
      final controller = ReportDetailController(
        repository: _FakeReportsRepository(detail: _detail()),
        reportId: 'r-1',
      );
      await settle();

      expect(controller.status, ReportDetailStatus.ready);
      expect(controller.report, isNotNull);
      expect(controller.report!.id, 'r-1');
      expect(controller.isMine, isFalse);
      expect(controller.supportCount, 2);
      expect(controller.isSupported, isFalse);
      expect(controller.detail!.activity, hasLength(1));
    });

    test('load failure moves to error state', () async {
      final controller = ReportDetailController(
        repository: _FakeReportsRepository(failLoad: true),
        reportId: 'r-1',
      );
      await settle();

      expect(controller.status, ReportDetailStatus.error);
      expect(controller.error, isA<ReportNotFoundException>());
    });

    test('toggleSupport optimistically adds support and persists it', () async {
      final repo = _FakeReportsRepository(detail: _detail());
      final controller = ReportDetailController(
        repository: repo,
        reportId: 'r-1',
      );
      await settle();

      await controller.toggleSupport();

      expect(controller.isSupported, isTrue);
      expect(controller.supportCount, 3);
      expect(repo.supportLog, ['add:r-1']);
      expect(controller.supportInFlight, isFalse);
    });

    test('toggleSupport optimistically withdraws and persists it', () async {
      final repo = _FakeReportsRepository(
        detail: _detail(report: _report(supportCount: 5)),
      );
      final controller = ReportDetailController(
        repository: repo,
        reportId: 'r-1',
      );
      await settle();

      controller.toggleSupport(); // add first
      await settle();
      await controller.toggleSupport(); // then withdraw

      expect(controller.isSupported, isFalse);
      expect(controller.supportCount, 5);
      expect(repo.supportLog, ['add:r-1', 'withdraw:r-1']);
    });

    test('toggleSupport reverts on repository failure', () async {
      final repo = _FakeReportsRepository(detail: _detail())
        ..supportFails = true;
      final controller = ReportDetailController(
        repository: repo,
        reportId: 'r-1',
      );
      await settle();

      await expectLater(controller.toggleSupport(), throwsException);

      expect(controller.isSupported, isFalse);
      expect(controller.supportCount, 2);
      expect(controller.supportInFlight, isFalse);
    });

    test('addComment appends the returned comment', () async {
      final controller = ReportDetailController(
        repository: _FakeReportsRepository(detail: _detail()),
        reportId: 'r-1',
      );
      await settle();

      await controller.addComment('  Please fix soon.  ');

      expect(controller.detail!.comments, hasLength(1));
      expect(controller.detail!.comments.first.id, 'c-new');
      expect(controller.detail!.comments.first.isMine, isTrue);
      expect(controller.commentInFlight, isFalse);
    });

    test('addComment ignores blank messages', () async {
      final controller = ReportDetailController(
        repository: _FakeReportsRepository(detail: _detail()),
        reportId: 'r-1',
      );
      await settle();

      await controller.addComment('   ');
      expect(controller.detail!.comments, isEmpty);
    });

    test('deleteComment removes the comment locally', () async {
      final withComment = _detail();
      final controller = ReportDetailController(
        repository: _FakeReportsRepository(detail: withComment),
        reportId: 'r-1',
      );
      await settle();

      await controller.addComment('hello');
      expect(controller.detail!.comments, hasLength(1));

      await controller.deleteComment('c-new');
      expect(controller.detail!.comments, isEmpty);
    });

    test('cancelReport delegates to the repository', () async {
      final repo = _FakeReportsRepository(detail: _detail());
      final controller = ReportDetailController(
        repository: repo,
        reportId: 'r-1',
      );
      await settle();

      expect(await controller.cancelReport(), isTrue);
      expect(controller.cancelling, isFalse);
    });

    test('uploadEvidence appends the file', () async {
      final controller = ReportDetailController(
        repository: _FakeReportsRepository(detail: _detail()),
        reportId: 'r-1',
      );
      await settle();

      await controller.uploadEvidence(
        filePath: 'C:/tmp/photo.png',
        contentType: 'image/png',
      );

      expect(controller.detail!.evidence, hasLength(1));
      expect(controller.detail!.evidence.first.fileType, 'image/png');
    });
  });
}
