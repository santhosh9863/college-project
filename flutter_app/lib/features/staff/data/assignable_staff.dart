/// A staff member eligible for assignment (from the ops/admin-only
/// `list_assignable_staff` RPC — profiles RLS hides other users' rows).
class AssignableStaff {
  const AssignableStaff({
    required this.id,
    required this.fullName,
    required this.role,
    this.departmentCode,
  });

  factory AssignableStaff.fromJson(Map<String, dynamic> json) => AssignableStaff(
        id: json['id'] as String,
        fullName: (json['full_name'] as String?) ?? '',
        role: (json['role'] as String?) ?? '',
        departmentCode: json['department_code'] as String?,
      );

  final String id;
  final String fullName;
  final String role;
  final String? departmentCode;
}