import 'report_priority.dart';
import 'report_status.dart';

/// A community report (`reports` table). Read-only for students — the only
/// student write is cancelling their own pending report (soft delete).
///
/// All reads are RLS-scoped: a student only ever sees reports from their
/// active community plus their own historical reports.
class Report {
  const Report({
    required this.id,
    required this.title,
    this.description = '',
    required this.categoryId,
    required this.categoryName,
    required this.priority,
    required this.status,
    required this.reporterId,
    required this.communityId,
    required this.supportCount,
    required this.createdAt,
    this.updatedAt,
    this.isMine = false,
    this.isSupported = false,
  });

  factory Report.fromJson(
    Map<String, dynamic> json, {
    required String currentUserId,
  }) {
    final category = json['categories'];
    return Report(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      categoryId: (json['category_id'] as String?) ?? '',
      categoryName: category is Map<String, dynamic>
          ? (category['name'] as String?) ?? 'General'
          : 'General',
      priority: ReportPriority.fromApi(json['priority'] as String?),
      status: ReportStatus.fromApi(json['status'] as String?),
      reporterId: (json['reporter_id'] as String?) ?? '',
      communityId: (json['community_id'] as String?) ?? '',
      supportCount: _supportCountFromJson(json),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      isMine: (json['reporter_id'] as String?) == currentUserId,
    );
  }

  final String id;
  final String title;
  final String description;
  final String categoryId;
  final String categoryName;
  final ReportPriority priority;
  final ReportStatus status;

  /// Author id. Never used as a security boundary — only for display ("You").
  final String reporterId;

  /// Snapshot community id. Never used as a security boundary — the database
  /// enforces community isolation via RLS.
  final String communityId;

  final int supportCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  /// Whether the authenticated student is the reporter (display only).
  final bool isMine;

  /// Whether the authenticated student has supported this report (display
  /// only; the database policy is the enforcement).
  final bool isSupported;

  Report copyWith({bool? isSupported, int? supportCount}) => Report(
        id: id,
        title: title,
        description: description,
        categoryId: categoryId,
        categoryName: categoryName,
        priority: priority,
        status: status,
        reporterId: reporterId,
        communityId: communityId,
        supportCount: supportCount ?? this.supportCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
        isMine: isMine,
        isSupported: isSupported ?? this.isSupported,
      );

  /// Parses the embedded `report_supports(count)` aggregate.
  static int _supportCountFromJson(Map<String, dynamic> json) {
    final raw = json['report_supports'];
    if (raw is! List || raw.isEmpty) return 0;
    final first = raw.first;
    if (first is! Map<String, dynamic>) return 0;
    return (first['count'] as num?)?.toInt() ?? 0;
  }
}
