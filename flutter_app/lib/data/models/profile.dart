/// Student profile returned by the auth service. Mirrors `profiles` columns;
/// `id` is the Supabase auth user id (profiles.id = auth.users.id by
/// construction — the client never generates identities).
class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    this.semester,
    this.section,
    required this.studentId,
  });

  final String id;
  final String fullName;
  final String email;
  final String role;
  final int? semester;
  final String? section;
  final String studentId;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] is String ? json['id'] as String : '',
      fullName: json['full_name'] is String ? json['full_name'] as String : '',
      email: json['email'] is String ? json['email'] as String : '',
      role: json['role'] is String ? json['role'] as String : 'student',
      semester: json['semester'] is int ? json['semester'] as int : null,
      section: json['section'] is String ? json['section'] as String : null,
      studentId: json['student_id'] is String ? json['student_id'] as String : '',
    );
  }

  bool get isValid => id.isNotEmpty && fullName.isNotEmpty;
}
