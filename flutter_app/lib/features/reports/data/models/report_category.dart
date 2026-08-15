/// A report category (`categories` table). Reference data — read-only, loaded
/// from the database (never hardcoded in the app).
class ReportCategory {
  const ReportCategory({required this.id, required this.name});

  factory ReportCategory.fromJson(Map<String, dynamic> json) => ReportCategory(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
      );

  final String id;
  final String name;
}
