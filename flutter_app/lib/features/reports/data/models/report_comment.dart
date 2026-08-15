/// A comment on a report (`report_comments` table). Students can add comments
/// on visible reports and delete their own; editing is not permitted by RLS.
class ReportComment {
  const ReportComment({
    required this.id,
    required this.reportId,
    required this.authorId,
    required this.message,
    required this.createdAt,
    this.isMine = false,
  });

  factory ReportComment.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    final authorId = (json['author_id'] as String?) ?? '';
    return ReportComment(
      id: (json['id'] as String?) ?? '',
      reportId: (json['report_id'] as String?) ?? '',
      authorId: authorId,
      message: (json['message'] as String?) ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isMine: authorId == currentUserId,
    );
  }

  final String id;
  final String reportId;
  final String authorId;
  final String message;
  final DateTime createdAt;

  /// Whether the authenticated student authored this comment (display only —
  /// RLS enforces deletion rights).
  final bool isMine;
}
