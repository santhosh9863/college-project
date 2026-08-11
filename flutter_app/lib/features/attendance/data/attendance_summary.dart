/// Overall attendance summary from the confirmed Linways endpoint
/// `GET /academics/api/v1/student/get-my-attendance-summary`.
///
/// Dashboard-only (MVP): never stored in Supabase, never persisted locally.
class AttendanceSummary {
  const AttendanceSummary({
    required this.totalHours,
    required this.attendedHours,
    required this.totalPresent,
    required this.attendancePercentage,
    required this.isHourWiseEnabled,
  });

  factory AttendanceSummary.fromJson(Map<String, dynamic> json) {
    return AttendanceSummary(
      totalHours: _asInt(json['totalHours']),
      attendedHours: _asInt(json['attendedHours']),
      totalPresent: _asInt(json['totalPresent']),
      attendancePercentage: _asDouble(json['attendancePercentage']),
      isHourWiseEnabled: json['isHourWiseEnabled'] == true,
    );
  }

  final int totalHours;
  final int attendedHours;
  final int totalPresent;
  final double? attendancePercentage;
  final bool isHourWiseEnabled;

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
