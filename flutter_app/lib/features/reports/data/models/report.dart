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
    this.duplicateOf,
    this.updatedAt,
    this.deletedAt,
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
      duplicateOf: _duplicateOfFromJson(json),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      isMine: (json['reporter_id'] as String?) == currentUserId,
      deletedAt: DateTime.tryParse(json['deleted_at'] as String? ?? ''),
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

  /// Id of an earlier report that this one looks like a repeat of, set by the
  /// AI-1 duplicate check (`20261005123000_ai1_duplicate_detection.sql`).
  ///
  /// **Advisory only.** It never means the report is invalid, and nothing may
  /// reject, merge, hide, or close it because of this value (CURRENT_STATE §8).
  /// The target is always in the same community and always canonical — the
  /// trigger excludes candidates that are themselves duplicates, so this can
  /// never point at another duplicate and no chain forms.
  final String? duplicateOf;

  /// Whether this report was flagged as a possible duplicate. Ignores a
  /// self-reference, so a row that (defensively) points at itself still renders
  /// as unflagged rather than showing a notice pointing at its own title.
  bool get isDuplicate {
    final target = duplicateOf;
    return target != null && target.isNotEmpty && target != id;
  }

  /// Soft-delete marker (`deleted_at`); set by student self-cancel or staff
  /// moderation, cleared only by admin restore. Never a client-side boundary —
  /// RLS is the enforcement.
  final DateTime? deletedAt;

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
        duplicateOf: duplicateOf,
        updatedAt: updatedAt,
        isMine: isMine,
        isSupported: isSupported ?? this.isSupported,
        deletedAt: deletedAt,
      );

  /// Parses the embedded `report_supports(count)` aggregate.
  static int _supportCountFromJson(Map<String, dynamic> json) {
    final raw = json['report_supports'];
    if (raw is! List || raw.isEmpty) return 0;
    final first = raw.first;
    if (first is! Map<String, dynamic>) return 0;
    return (first['count'] as num?)?.toInt() ?? 0;
  }

  /// Reads `duplicate_of`, normalising absent/blank/!string values to null so
  /// callers never have to distinguish "not flagged" from "flagged with junk".
  static String? _duplicateOfFromJson(Map<String, dynamic> json) {
    final raw = json['duplicate_of'];
    if (raw is! String) return null;
    final value = raw.trim();
    return value.isEmpty ? null : value;
  }
}
