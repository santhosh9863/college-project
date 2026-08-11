/// A community report (reports table). For the MVP dashboard this is a
/// read-only projection; all writes and lifecycle transitions belong to later
/// phases.
class Report {
  const Report({
    required this.id,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    required this.categoryName,
    required this.createdAt,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    final category = json['categories'];
    return Report(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      priority: (json['priority'] as String?) ?? 'medium',
      categoryName: category is Map<String, dynamic>
          ? (category['name'] as String?) ?? 'General'
          : 'General',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String title;
  final String? description;
  final String status;
  final String priority;
  final String categoryName;
  final DateTime? createdAt;
}
