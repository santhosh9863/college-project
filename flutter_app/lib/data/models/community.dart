/// Academic community as derived server-side by the auth service. The client
/// never supplies course/year/semester/section — this is display data only.
class Community {
  const Community({
    required this.courseCode,
    required this.batchYear,
    required this.semester,
    required this.section,
  });

  final String courseCode;
  final int batchYear;
  final String semester;
  final String section;

  String get displayName => '$courseCode $batchYear $semester $section';

  factory Community.fromJson(Map<String, dynamic> json) {
    return Community(
      courseCode: json['course_code'] is String ? json['course_code'] as String : '',
      batchYear: json['batch_year'] is int ? json['batch_year'] as int : 0,
      semester: json['semester'] is String ? json['semester'] as String : '',
      section: json['section'] is String ? json['section'] as String : '',
    );
  }

  bool get isValid =>
      courseCode.isNotEmpty && batchYear > 0 && semester.isNotEmpty && section.isNotEmpty;
}
