import 'package:college_project_app/features/reports/data/evidence_mime.dart';
import 'package:college_project_app/features/reports/data/models/evidence_file.dart';
import 'package:college_project_app/features/reports/data/models/report.dart';
import 'package:college_project_app/features/reports/data/models/report_activity_item.dart';
import 'package:college_project_app/features/reports/data/models/report_category.dart';
import 'package:college_project_app/features/reports/data/models/report_comment.dart';
import 'package:college_project_app/features/reports/data/models/report_priority.dart';
import 'package:college_project_app/features/reports/data/models/report_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReportStatus', () {
    test('parses api values', () {
      expect(ReportStatus.fromApi('pending'), ReportStatus.pending);
      expect(ReportStatus.fromApi('under_review'), ReportStatus.underReview);
      expect(ReportStatus.fromApi('in_progress'), ReportStatus.inProgress);
      expect(ReportStatus.fromApi('resolved'), ReportStatus.resolved);
      expect(ReportStatus.fromApi('rejected'), ReportStatus.rejected);
      expect(ReportStatus.fromApi('closed'), ReportStatus.closed);
    });

    test('unknown api value maps to unknown with empty apiValue', () {
      final status = ReportStatus.fromApi('bogus');
      expect(status, ReportStatus.unknown);
      expect(status.apiValue, '');
    });

    test('labels are user facing', () {
      expect(ReportStatus.pending.label, 'Pending');
      expect(ReportStatus.underReview.label, 'Under review');
      expect(ReportStatus.inProgress.label, 'In progress');
    });
  });

  group('ReportPriority', () {
    test('parses api values including critical', () {
      expect(ReportPriority.fromApi('low'), ReportPriority.low);
      expect(ReportPriority.fromApi('medium'), ReportPriority.medium);
      expect(ReportPriority.fromApi('high'), ReportPriority.high);
      expect(ReportPriority.fromApi('critical'), ReportPriority.critical);
    });

    test('unknown maps to unknown', () {
      expect(ReportPriority.fromApi(null), ReportPriority.unknown);
    });
  });

  group('Report', () {
    Map<String, dynamic> row({
      String status = 'pending',
      String priority = 'medium',
      String reporterId = 'user-b',
      String categoryName = 'Academic',
      List<dynamic> supports = const [
        {'count': 3},
      ],
    }) =>
        {
          'id': 'report-1',
          'title': 'Broken projector',
          'description': 'Projector in room 12 is broken.',
          'status': status,
          'priority': priority,
          'category_id': 'cat-1',
          'categories': {'name': categoryName},
          'reporter_id': reporterId,
          'community_id': 'community-1',
          'report_supports': supports,
          'created_at': '2026-08-15T10:00:00.000Z',
          'updated_at': '2026-08-15T11:00:00.000Z',
        };

    test('parses full row with embedded category and support count', () {
      final report = Report.fromJson(row(), currentUserId: 'user-a');
      expect(report.id, 'report-1');
      expect(report.title, 'Broken projector');
      expect(report.status, ReportStatus.pending);
      expect(report.priority, ReportPriority.medium);
      expect(report.categoryId, 'cat-1');
      expect(report.categoryName, 'Academic');
      expect(report.communityId, 'community-1');
      expect(report.supportCount, 3);
      expect(report.createdAt, DateTime.parse('2026-08-15T10:00:00.000Z'));
      expect(report.isMine, isFalse);
      expect(report.isSupported, isFalse);
    });

    test('marks own reports', () {
      final report = Report.fromJson(row(reporterId: 'user-a'), currentUserId: 'user-a');
      expect(report.isMine, isTrue);
    });

    test('tolerates missing category and support embeds', () {
      final report = Report.fromJson(
        row()
          ..remove('categories')
          ..remove('report_supports'),
        currentUserId: 'user-a',
      );
      expect(report.categoryName, 'General');
      expect(report.supportCount, 0);
    });

    test('copyWith keeps identity flags', () {
      final report = Report.fromJson(row(), currentUserId: 'user-a');
      final supported = report.copyWith(isSupported: true, supportCount: 4);
      expect(supported.isSupported, isTrue);
      expect(supported.supportCount, 4);
      expect(supported.isMine, report.isMine);
    });
  });

  group('ReportCategory', () {
    test('parses id and name', () {
      final category =
          ReportCategory.fromJson({'id': 'cat-1', 'name': 'Academic'});
      expect(category.id, 'cat-1');
      expect(category.name, 'Academic');
    });
  });

  group('ReportComment', () {
    test('parses and marks own comments', () {
      final comment = ReportComment.fromJson({
        'id': 'c-1',
        'report_id': 'r-1',
        'author_id': 'user-a',
        'message': 'Same issue here.',
        'created_at': '2026-08-15T10:00:00.000Z',
      }, currentUserId: 'user-a');
      expect(comment.isMine, isTrue);
      expect(comment.message, 'Same issue here.');
    });

    test('marks other comments', () {
      final comment = ReportComment.fromJson({
        'id': 'c-1',
        'report_id': 'r-1',
        'author_id': 'user-b',
        'message': 'Hello',
        'created_at': '2026-08-15T10:00:00.000Z',
      }, currentUserId: 'user-a');
      expect(comment.isMine, isFalse);
    });
  });

  group('ReportActivityItem', () {
    ReportActivityItem item(String type, [Map<String, dynamic>? metadata]) =>
        ReportActivityItem.fromJson({
          'id': 'a-1',
          'report_id': 'r-1',
          'actor_id': 'user-a',
          'activity_type': type,
          'metadata': metadata ?? {},
          'created_at': '2026-08-15T10:00:00.000Z',
        });

    test('created', () => expect(item('created').displayMessage, 'Report created'));

    test('status transitions', () {
      expect(
        item('status_change', {'from_status': 'pending', 'to_status': 'under_review'})
            .displayMessage,
        'Moved to under review',
      );
      expect(
        item('status_change', {'from_status': 'under_review', 'to_status': 'in_progress'})
            .displayMessage,
        'Moved to in progress',
      );
      expect(
        item('status_change', {'from_status': 'in_progress', 'to_status': 'resolved'})
            .displayMessage,
        'Report resolved',
      );
      expect(
        item('status_change', {'from_status': 'pending', 'to_status': 'rejected'})
            .displayMessage,
        'Report rejected',
      );
      expect(
        item('status_change', {'from_status': 'in_progress', 'to_status': 'closed'})
            .displayMessage,
        'Report closed',
      );
    });

    test('reopen', () {
      expect(
        item('status_change', {'from_status': 'rejected', 'to_status': 'in_progress'})
            .displayMessage,
        'Report reopened',
      );
    });

    test('assignments and deletions', () {
      expect(item('assigned').displayMessage, 'Report assigned to staff');
      expect(item('unassigned').displayMessage, 'Assignment removed');
      expect(item('restored').displayMessage, 'Report restored');
      expect(
        item('soft_deleted', {'deleted_by': 'student'}).displayMessage,
        'Report cancelled',
      );
      expect(
        item('soft_deleted', {'deleted_by': 'staff'}).displayMessage,
        'Report deleted',
      );
    });

    test('unknown types fall back to generic', () {
      expect(item('mystery').displayMessage, 'Activity recorded');
    });
  });

  group('EvidenceFile', () {
    test('parses and marks own uploads', () {
      final file = EvidenceFile.fromJson({
        'id': 'e-1',
        'report_id': 'r-1',
        'file_url': 'evidence/r-1/1_photo.png',
        'file_type': 'image/png',
        'uploaded_by': 'user-a',
        'created_at': '2026-08-15T10:00:00.000Z',
      }, currentUserId: 'user-a');
      expect(file.fileUrl, 'evidence/r-1/1_photo.png');
      expect(file.fileType, 'image/png');
      expect(file.isMine, isTrue);
    });
  });

  group('evidenceMimeTypeFromName', () {
    test('maps supported extensions', () {
      expect(evidenceMimeTypeFromName('a.png'), 'image/png');
      expect(evidenceMimeTypeFromName('a.JPG'), 'image/jpeg');
      expect(evidenceMimeTypeFromName('a.jpeg'), 'image/jpeg');
      expect(evidenceMimeTypeFromName('a.webp'), 'image/webp');
      expect(evidenceMimeTypeFromName('a.heic'), 'image/heic');
      expect(evidenceMimeTypeFromName('a.pdf'), 'application/pdf');
    });

    test('unknown extensions fall back to octet-stream (server rejects)', () {
      expect(evidenceMimeTypeFromName('a.exe'), 'application/octet-stream');
    });
  });
}
