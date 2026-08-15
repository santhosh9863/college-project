/// One row of the `report_activity` timeline. Server-generated only — the
/// client never inserts activity rows.
class ReportActivityItem {
  const ReportActivityItem({
    required this.id,
    required this.reportId,
    required this.actorId,
    required this.activityType,
    this.metadata = const {},
    required this.createdAt,
  });

  factory ReportActivityItem.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'];
    return ReportActivityItem(
      id: (json['id'] as String?) ?? '',
      reportId: (json['report_id'] as String?) ?? '',
      actorId: (json['actor_id'] as String?) ?? '',
      activityType: (json['activity_type'] as String?) ?? '',
      metadata: metadata is Map<String, dynamic> ? metadata : const {},
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String id;
  final String reportId;
  final String actorId;
  final String activityType;
  final Map<String, dynamic> metadata;
  final DateTime createdAt;

  /// User-facing description of this event. Sensitive internal metadata is
  /// never surfaced here.
  String get displayMessage {
    switch (activityType) {
      case 'created':
        return 'Report created';
      case 'status_change':
        final to = metadata['to_status'] as String?;
        final from = metadata['from_status'] as String?;
        if (from == 'resolved' || from == 'rejected') return 'Report reopened';
        return switch (to) {
          'under_review' => 'Moved to under review',
          'in_progress' => 'Moved to in progress',
          'resolved' => 'Report resolved',
          'rejected' => 'Report rejected',
          'closed' => 'Report closed',
          _ => 'Status updated',
        };
      case 'assigned':
        return 'Report assigned to staff';
      case 'unassigned':
        return 'Assignment removed';
      case 'soft_deleted':
        return metadata['deleted_by'] == 'student'
            ? 'Report cancelled'
            : 'Report deleted';
      case 'restored':
        return 'Report restored';
      default:
        return 'Activity recorded';
    }
  }
}
