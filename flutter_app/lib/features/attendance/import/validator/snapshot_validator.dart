import '../../../../data/models/community.dart';
import '../../../../data/models/profile.dart';
import '../models/parsed_linways_snapshot.dart';
import '../models/validation_issue.dart';

/// Cross-checks a parsed snapshot against itself and against the
/// authenticated profile/community.
///
/// - The authenticated profile is authoritative for identity — a screenshot
///   difference is a WARNING, never a change to the community.
/// - Missing optional fields are INFO, never blockers.
/// - Invalid counts are ERROR and block confirmation.
class SnapshotValidator {
  const SnapshotValidator();

  List<ValidationIssue> validate(
    ParsedLinwaysSnapshot snapshot, {
    Profile? profile,
    Community? community,
  }) {
    final issues = <ValidationIssue>[...snapshot.warnings];

    _validateOverall(snapshot.overall, issues);
    _validateSubjects(snapshot.subjects, issues);
    _validateIdentity(snapshot.identity, issues, profile, community);
    _validateOptionalInfo(snapshot, issues);

    issues.sort((a, b) {
      final rank = a.sortRank.compareTo(b.sortRank);
      return rank != 0 ? rank : a.message.compareTo(b.message);
    });
    return _dedupe(issues);
  }

  static void _validateOverall(
    ParsedOverallAttendance overall,
    List<ValidationIssue> issues,
  ) {
    final conducted = overall.conducted.value;
    final attended = overall.attended.value;
    final absent = overall.absent.value;
    final percentage = overall.percentage.value;

    if (conducted != null && attended != null && attended > conducted) {
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'invalidCounts',
        message: 'Attendance counts are invalid (attended > conducted).',
        field: 'overall.attended',
      ));
    }
    if (conducted != null && absent != null && absent > conducted) {
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'invalidCounts',
        message: 'Attendance counts are invalid (absent > conducted).',
        field: 'overall.absent',
      ));
    }
    if (percentage != null && (percentage < 0 || percentage > 100)) {
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'invalidPercentage',
        message: 'Attendance percentage is outside 0–100.',
        field: 'overall.percentage',
      ));
    }
  }

  static void _validateSubjects(
    List<ParsedSubjectAttendance> subjects,
    List<ValidationIssue> issues,
  ) {
    for (final subject in subjects) {
      final conducted = subject.conducted.value;
      final attended = subject.attended.value;
      final absent = subject.absent.value;
      final percentage = subject.percentage.value;

      if (percentage != null && (percentage < 0 || percentage > 100)) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'invalidPercentage',
          message: 'Percentage for "${subject.name.value}" is outside 0–100.',
          field: 'subjects.percentage',
        ));
      }
      if (conducted != null && attended != null && attended > conducted) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'invalidCounts',
          message: 'Attendance counts are invalid for "${subject.name.value}".',
          field: 'subjects',
        ));
      }
      if (conducted != null && absent != null && absent > conducted) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.error,
          code: 'invalidCounts',
          message: 'Attendance counts are invalid for "${subject.name.value}".',
          field: 'subjects',
        ));
      }
    }
  }

  static void _validateIdentity(
    ParsedIdentity identity,
    List<ValidationIssue> issues,
    Profile? profile,
    Community? community,
  ) {
    if (profile == null && community == null) return;

    final section = identity.section.value;
    if (section != null && profile?.section != null &&
        !_equalsIgnoreCase(section, profile!.section!)) {
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'identitySectionMismatch',
        message: 'Student section differs from your registered profile.',
        field: 'identity.section',
      ));
    }

    final semester = identity.semester.value;
    final semesterDigits = _digitsOnly(semester);
    if (semesterDigits.isNotEmpty && profile?.semester != null &&
        semesterDigits != profile!.semester.toString()) {
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'identitySemesterMismatch',
        message: 'Student semester differs from your registered profile.',
        field: 'identity.semester',
      ));
    }

    final department = identity.department.value;
    if (department != null && community != null &&
        community.courseCode.isNotEmpty &&
        !_equalsIgnoreCase(department, community.courseCode)) {
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'identityDepartmentMismatch',
        message:
            'Screenshot information differs from your registered profile (department ${_short(department)} vs ${community.courseCode}).',
        field: 'identity.department',
      ));
    }

    final yearDigits = _digitsOnly(identity.batch.value);
    if (yearDigits.isNotEmpty && community != null && community.batchYear > 0 &&
        yearDigits != community.batchYear.toString()) {
      issues.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'identityBatchMismatch',
        message:
            'Screenshot information differs from your registered profile (batch year ${_short(identity.batch.value!)} vs ${community.batchYear}).',
        field: 'identity.batch',
      ));
    }
  }

  static void _validateOptionalInfo(
    ParsedLinwaysSnapshot snapshot,
    List<ValidationIssue> issues,
  ) {
    if (snapshot.hasAnyAttendance) {
      if (snapshot.subjects.any((s) => s.name.isPresent) &&
          snapshot.subjects.every((s) => s.code.isMissing)) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.info,
          code: 'subjectCodeMissing',
          message: 'Subject code was not visible in the screenshot.',
          field: 'subjects.code',
        ));
      }
      if (snapshot.identity.studentName.isMissing) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.info,
          code: 'studentNameMissing',
          message: 'Student name was not visible in the screenshot.',
          field: 'identity.studentName',
        ));
      }
    }
  }

  static bool _equalsIgnoreCase(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  static String _digitsOnly(String? value) =>
      value == null ? '' : value.replaceAll(RegExp(r'[^0-9]'), '');

  static String _short(String value) =>
      value.length <= 12 ? value : '${value.substring(0, 12)}…';

  static List<ValidationIssue> _dedupe(List<ValidationIssue> issues) {
    final seen = <String>{};
    final result = <ValidationIssue>[];
    for (final issue in issues) {
      final key = '${issue.code}|${issue.field}|${issue.message}';
      if (seen.add(key)) result.add(issue);
    }
    return result;
  }
}