/// An in-app notification (notifications table, user-scoped by RLS).
/// Read-only for MVP: marking read is the only supported write.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.referenceId,
    required this.read,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'general',
      referenceId: json['reference_id'] as String?,
      read: json['read'] == true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String title;
  final String body;
  final String type;
  final String? referenceId;
  final bool read;
  final DateTime? createdAt;
}
