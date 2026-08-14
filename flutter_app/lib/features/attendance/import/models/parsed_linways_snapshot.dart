import 'provenance.dart';
import 'validation_issue.dart';

/// Conceptual Linways screen types supported by the importer.
enum LinwaysScreenType {
  /// Overall attendance: percentage and/or total/attended/absent counts.
  overallAttendance,

  /// Subject-wise attendance table.
  subjectWiseAttendance,

  /// Student/profile information.
  studentProfile,

  /// No supported layout was recognized.
  unknown,
}

/// Source metadata for a parsed snapshot.
class ParsedSource {
  const ParsedSource({
    required this.screenType,
    required this.screenConfidence,
    required this.capturedAt,
  });

  final LinwaysScreenType screenType;

  /// 0..1 detector confidence. A low value means the layout was uncertain but
  /// extraction still continued.
  final double? screenConfidence;

  final DateTime capturedAt;

  bool get typeUncertain => screenType == LinwaysScreenType.unknown;
}

/// Identity/context fields parsed from the screenshot. Corroborative only —
/// the authenticated profile is authoritative (see ADR-005 §2.5).
class ParsedIdentity {
  const ParsedIdentity({
    this.studentName = const ProvenanceValue.missing(),
    this.studentId = const ProvenanceValue.missing(),
    this.department = const ProvenanceValue.missing(),
    this.semester = const ProvenanceValue.missing(),
    this.section = const ProvenanceValue.missing(),
    this.batch = const ProvenanceValue.missing(),
    this.academicYear = const ProvenanceValue.missing(),
  });

  final ProvenanceValue<String> studentName;
  final ProvenanceValue<String> studentId;
  final ProvenanceValue<String> department;
  final ProvenanceValue<String> semester;
  final ProvenanceValue<String> section;
  final ProvenanceValue<String> batch;
  final ProvenanceValue<String> academicYear;
}

/// Overall attendance figures.
class ParsedOverallAttendance {
  const ParsedOverallAttendance({
    this.conducted = const ProvenanceValue.missing(),
    this.attended = const ProvenanceValue.missing(),
    this.absent = const ProvenanceValue.missing(),
    this.percentage = const ProvenanceValue.missing(),
    this.status = const ProvenanceValue.missing(),
  });

  final ProvenanceValue<int> conducted;
  final ProvenanceValue<int> attended;
  final ProvenanceValue<int> absent;
  final ProvenanceValue<double> percentage;

  /// Display-only category derived from [percentage].
  final ProvenanceValue<String> status;

  bool get hasCounts => conducted.isPresent && attended.isPresent;
  bool get hasAny => hasCounts || percentage.isPresent;
}

/// One subject row from a subject-wise attendance table.
class ParsedSubjectAttendance {
  const ParsedSubjectAttendance({
    this.name = const ProvenanceValue.missing(),
    this.code = const ProvenanceValue.missing(),
    this.faculty = const ProvenanceValue.missing(),
    this.conducted = const ProvenanceValue.missing(),
    this.attended = const ProvenanceValue.missing(),
    this.absent = const ProvenanceValue.missing(),
    this.percentage = const ProvenanceValue.missing(),
  });

  final ProvenanceValue<String> name;
  final ProvenanceValue<String> code;
  final ProvenanceValue<String> faculty;
  final ProvenanceValue<int> conducted;
  final ProvenanceValue<int> attended;
  final ProvenanceValue<int> absent;
  final ProvenanceValue<double> percentage;

  /// Whether this row is worth showing. `_parseRow` already rejects junk
  /// lines, so a readable subject name is enough — a row whose values were
  /// nulled by OCR-noise suspicion is still surfaced (with its warning).
  bool get isValid => name.isPresent;

  /// Stable key used for duplicate detection (name + code when visible).
  String get dedupeKey =>
      '${name.value ?? ''}|${code.value ?? ''}'.trim().toLowerCase();
}

/// P2 optional information captured only when clearly visible. Never blocks
/// P0/P1 extraction.
class ParsedOptionalInfo {
  const ParsedOptionalInfo({
    this.timetable = const ProvenanceValue.missing(),
    this.period = const ProvenanceValue.missing(),
    this.classroom = const ProvenanceValue.missing(),
    this.examInfo = const ProvenanceValue.missing(),
    this.marks = const ProvenanceValue.missing(),
  });

  final ProvenanceValue<String> timetable;
  final ProvenanceValue<String> period;
  final ProvenanceValue<String> classroom;
  final ProvenanceValue<String> examInfo;
  final ProvenanceValue<String> marks;
}

/// Fully parsed result of one imported Linways screenshot.
///
/// Lives in memory only (controller state). Never persisted, never uploaded,
/// never logged.
class ParsedLinwaysSnapshot {
  const ParsedLinwaysSnapshot({
    required this.source,
    this.identity = const ParsedIdentity(),
    this.overall = const ParsedOverallAttendance(),
    this.subjects = const [],
    this.attendanceDate = const ProvenanceValue.missing(),
    this.optional = const ParsedOptionalInfo(),
    this.warnings = const [],
  });

  final ParsedSource source;
  final ParsedIdentity identity;
  final ParsedOverallAttendance overall;
  final List<ParsedSubjectAttendance> subjects;

  /// Date/period the attendance is reported as of, when visible.
  final ProvenanceValue<String> attendanceDate;

  final ParsedOptionalInfo optional;

  /// Issues found during parsing (conflicts, duplicates, noise, uncertainty).
  final List<ValidationIssue> warnings;

  bool get hasAnyAttendance => overall.hasAny || subjects.isNotEmpty;
}