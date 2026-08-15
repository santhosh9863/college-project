import 'evidence_file.dart';
import 'report.dart';
import 'report_activity_item.dart';
import 'report_comment.dart';

/// Fully loaded report detail: the report plus its comments, evidence,
/// activity timeline and (when visible) the active assignee.
class ReportDetail {
  const ReportDetail({
    required this.report,
    this.comments = const [],
    this.evidence = const [],
    this.activity = const [],
    this.activeAssigneeId,
  });

  final Report report;
  final List<ReportComment> comments;
  final List<EvidenceFile> evidence;
  final List<ReportActivityItem> activity;

  /// Id of the staff member currently assigned, when visible to the caller.
  /// Display-only: names are not readable by students (identity policy), so
  /// the UI shows a generic label.
  final String? activeAssigneeId;
}
