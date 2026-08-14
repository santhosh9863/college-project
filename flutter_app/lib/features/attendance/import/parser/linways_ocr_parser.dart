import '../models/parsed_linways_snapshot.dart';
import '../models/provenance.dart';
import '../models/validation_issue.dart';
import 'attendance_table_parser.dart';
import 'linways_screen_detector.dart';
import 'ocr_text.dart';
import 'pattern_helpers.dart';

/// Structured parser: OCR text → [ParsedLinwaysSnapshot].
///
/// Rules (ADR-005):
/// - Extract only what is visible. Never guess missing values.
/// - Derive only when mathematically supported (absent = conducted − attended,
///   percentage = attended ÷ conducted × 100).
/// - A visible value that conflicts with a derivation is preserved and a
///   warning is generated.
class LinwaysOcrParser {
  const LinwaysOcrParser({this.detector = const LinwaysScreenDetector()});

  final LinwaysScreenDetector detector;

  /// Case-insensitive regex (Dart RegExp has no inline `(?i)` flag).
  static RegExp re(String source) => RegExp(source, caseSensitive: false);

  ParsedLinwaysSnapshot parse(String rawOcrText, {DateTime? capturedAt}) {
    final lines = splitOcrText(rawOcrText);
    final warnings = <ValidationIssue>[];

    final detection = detector.detect(lines);
    if (detection.type == LinwaysScreenType.unknown) {
      warnings.add(const ValidationIssue(
        severity: ValidationSeverity.info,
        code: 'screenTypeUncertain',
        message: 'The screenshot layout was not fully recognized — extracting what is visible.',
      ));
    }

    final identity = _parseIdentity(lines);
    final overall = _parseOverall(lines, warnings);
    final subjects = const AttendanceTableParser()
        .parse(lines, warnings: warnings)
        .cast<ParsedSubjectAttendance>();
    final date = _parseDate(lines);
    final optional = _parseOptional(lines);

    if (!_hasAnyAttendance(overall, subjects)) {
      warnings.add(const ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'noAttendanceData',
        message: 'No attendance data could be read from this screenshot.',
      ));
    }

    return ParsedLinwaysSnapshot(
      source: ParsedSource(
        screenType: detection.type,
        screenConfidence: detection.type == LinwaysScreenType.unknown
            ? null
            : detection.confidence,
        capturedAt: capturedAt ?? DateTime.now(),
      ),
      identity: identity,
      overall: overall,
      subjects: subjects,
      attendanceDate: date,
      optional: optional,
      warnings: warnings,
    );
  }

  static bool _hasAnyAttendance(ParsedOverallAttendance overall, List<dynamic> subjects) =>
      overall.hasAny || subjects.isNotEmpty;

  // ---------------------------------------------------------------------------
  // Identity
  // ---------------------------------------------------------------------------

  ParsedIdentity _parseIdentity(List<OcrLine> lines) {
    var name = const ProvenanceValue<String>.missing();
    var studentId = const ProvenanceValue<String>.missing();
    var department = const ProvenanceValue<String>.missing();
    var semester = const ProvenanceValue<String>.missing();
    var section = const ProvenanceValue<String>.missing();
    var batch = const ProvenanceValue<String>.missing();
    var academicYear = const ProvenanceValue<String>.missing();

    for (final line in lines) {
      name = name.isMissing
          ? _labelValue(line, re(r'(?:student\s+)?name\s*[:.]?\s+(\S.+)'))
          : name;
      studentId = studentId.isMissing
          ? _labelValue(
              line,
              re(
                r'(?:register\s*(?:no\.?|number|id)?|roll\s*(?:no\.?|number)?|admission\s*(?:no\.?|number)?|usn|student\s*(?:id|number))\s*[:.]?\s+([A-Za-z0-9\-/]+)',
              ),
            )
          : studentId;
      department = department.isMissing ? _departmentValue(line) : department;
      semester = semester.isMissing
          ? _labelValue(line, re(r'(?:semester|current\s+sem|sem)\s*[:.]?\s+([A-Za-z0-9]+)'))
          : semester;
      section = section.isMissing
          ? _labelValue(line, re(r'section\s*[:.]?\s+([A-Za-z0-9]+)'))
          : section;
      batch = batch.isMissing
          ? _labelValue(line, re(r'batch\s*[:.]?\s+(\S.+)'))
          : batch;

      final year = TextPatterns.academicYearToken.firstMatch(line.normalized);
      if (academicYear.isMissing && year != null) {
        academicYear = ProvenanceValue.extracted(year.group(1)!.replaceAll(' ', ''));
      }
    }

    return ParsedIdentity(
      studentName: name,
      studentId: studentId,
      department: department,
      semester: semester,
      section: section,
      batch: batch,
      academicYear: academicYear,
    );
  }

  /// Value of the first capturing group of [pattern] on [line], or MISSING.
  static ProvenanceValue<String> _labelValue(OcrLine line, RegExp pattern) {
    final match = pattern.firstMatch(line.normalized);
    if (match == null) return const ProvenanceValue.missing();
    final value = match.group(1)!.trim();
    if (value.isEmpty) return const ProvenanceValue.missing();
    return ProvenanceValue.extracted(value);
  }

  /// Department/programme value. Guards against `Course Code:` style labels
  /// capturing their continuation text.
  static ProvenanceValue<String> _departmentValue(OcrLine line) {
    final match = re(
      r'(?:department|dept\.?|programme|program|cour?se|branch)\s*[:.]?\s+(\S.+)',
    ).firstMatch(line.normalized);
    if (match == null) return const ProvenanceValue.missing();
    final value = match.group(1)!.trim();
    final lowered = value.toLowerCase();
    if (value.isEmpty ||
        lowered.startsWith('code') ||
        lowered.startsWith(' name') ||
        lowered.startsWith('number')) {
      return const ProvenanceValue.missing();
    }
    return ProvenanceValue.extracted(value);
  }

  // ---------------------------------------------------------------------------
  // Overall attendance
  // ---------------------------------------------------------------------------

  ParsedOverallAttendance _parseOverall(List<OcrLine> lines, List<ValidationIssue> warnings) {
    int? conducted;
    int? attended;
    int? absent;
    double? percentage;
    String? suspiciousField;

    for (final line in lines) {
      final normalized = line.normalized;

      final conductedMatch =
          re(r'(?:total\s+)?(?:classes?\s+)?(?:conducted)\s*[:.]?\s+(\S+)')
                  .firstMatch(normalized) ??
              re(r'total\s+(?:classes?)\s*[:.]?\s+(\S+)').firstMatch(normalized);
      if (conducted == null && conductedMatch != null) {
        final v = _cleanInt(conductedMatch.group(1)!);
        if (v != null) {
          conducted = v;
        } else if (TextPatterns.isSuspiciousNumeric(conductedMatch.group(1)!)) {
          suspiciousField = 'overall.conducted';
        }
      }

      final attendedMatch =
          re(r'(?:classes?\s+)?(?:attended|present)\s*[:.]?\s+(\S+)').firstMatch(normalized);
      if (attended == null && attendedMatch != null) {
        final v = _cleanInt(attendedMatch.group(1)!);
        if (v != null) {
          attended = v;
        } else if (TextPatterns.isSuspiciousNumeric(attendedMatch.group(1)!)) {
          suspiciousField = 'overall.attended';
        }
      }

      final absentMatch =
          re(r'(?:classes?\s+)?(?:absent|absences)\s*[:.]?\s+(\S+)').firstMatch(normalized);
      if (absent == null && absentMatch != null) {
        final v = _cleanInt(absentMatch.group(1)!);
        if (v != null) {
          absent = v;
        } else if (TextPatterns.isSuspiciousNumeric(absentMatch.group(1)!)) {
          suspiciousField = 'overall.absent';
        }
      }

      if (percentage == null) {
        final pctMatch = re(
          r'(?:attendance\s*(?:percentage|%)|overall\s+attendance)\s*[:.]?\s*(\d{1,3}(?:\.\d{1,2})?)\s*%',
        ).firstMatch(normalized);
        if (pctMatch != null) {
          percentage = double.parse(pctMatch.group(1)!);
        } else if (TextPatterns.percentageIn(normalized) != null &&
            _isStandalonePercentageLine(line)) {
          percentage = TextPatterns.percentageIn(normalized);
        }
      }
    }

    if (suspiciousField != null) {
      warnings.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'suspiciousOcrNumber',
        message: 'A labelled attendance number looked ambiguous (O/I/L vs 0/1) and was not read.',
        field: suspiciousField,
      ));
    }

    final overall = ParsedOverallAttendance(
      conducted: conducted == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(conducted),
      attended: attended == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(attended),
      absent: absent == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(absent),
      percentage: percentage == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(percentage),
    );

    return _applyDerivations(overall, warnings);
  }

  /// absent = conducted − attended and percentage = attended ÷ conducted × 100
  /// only when missing and mathematically supported. Conflicts are preserved
  /// and warned about, never overwritten.
  static ParsedOverallAttendance _applyDerivations(
    ParsedOverallAttendance overall,
    List<ValidationIssue> warnings,
  ) {
    var conducted = overall.conducted;
    var attended = overall.attended;
    var absent = overall.absent;
    var percentage = overall.percentage;

    if (absent.isMissing && conducted.isPresent && attended.isPresent) {
      final derivedAbsent = conducted.value! - attended.value!;
      if (derivedAbsent >= 0) {
        absent = ProvenanceValue.derived(derivedAbsent);
      }
    } else if (absent.isPresent && conducted.isPresent && attended.isPresent) {
      final derived = conducted.value! - attended.value!;
      if (absent.value != derived) {
        warnings.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'absentMismatch',
          message:
              'Screenshot shows $absent absent, but the counts calculate $derived.',
          field: 'overall.absent',
        ));
      }
    }

    if (percentage.isMissing && conducted.isPresent && attended.isPresent && conducted.value! > 0) {
      percentage = ProvenanceValue.derived(attended.value! / conducted.value! * 100);
    } else if (percentage.isPresent && conducted.isPresent && attended.isPresent &&
        conducted.value! > 0) {
      final calculated = attended.value! / conducted.value! * 100;
      if ((percentage.value! - calculated).abs() > 0.05) {
        warnings.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'percentageMismatch',
          message:
              'Screenshot shows ${percentage.value!.toStringAsFixed(1)}%, but the counts calculate ${calculated.toStringAsFixed(1)}%.',
          field: 'overall.percentage',
        ));
      }
    }

    final statusValue = percentage.isPresent ? _statusLabel(percentage.value!) : null;

    return ParsedOverallAttendance(
      conducted: conducted,
      attended: attended,
      absent: absent,
      percentage: percentage,
      status: statusValue == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.derived(statusValue),
    );
  }

  static String _statusLabel(double percentage) {
    if (percentage < 75) return 'Low';
    if (percentage < 85) return 'Moderate';
    return 'Good';
  }

  static int? _cleanInt(String raw) {
    final cleaned = raw.replaceAll(',', '');
    if (!RegExp(r'^\d{1,4}$').hasMatch(cleaned)) return null;
    return int.parse(cleaned);
  }

  static bool _isStandalonePercentageLine(OcrLine line) {
    final rest = line.normalized
        .replaceAll(TextPatterns.pctToken, ' ')
        .replaceAll(RegExp(r'[%0-9.\s]'), '');
    return rest.isEmpty ||
        RegExp(r'^(attendance|overall|percentage|as of|as on|updated|report)?$',
                caseSensitive: false)
            .hasMatch(rest.trim());
  }

  // ---------------------------------------------------------------------------
  // Date & P2
  // ---------------------------------------------------------------------------

  static ProvenanceValue<String> _parseDate(List<OcrLine> lines) {
    final dateLines = [
      for (final line in lines)
        if (RegExp(r'\b(date|as on|as of|updated|report)\b', caseSensitive: false)
            .hasMatch(line.lower))
          line,
    ];
    final candidates = dateLines.isEmpty ? lines : dateLines;
    for (final line in candidates) {
      final match = TextPatterns.dateToken.firstMatch(line.normalized);
      if (match != null) {
        return ProvenanceValue.extracted(match.group(0)!);
      }
    }
    return const ProvenanceValue.missing();
  }

  ParsedOptionalInfo _parseOptional(List<OcrLine> lines) {
    var timetable = const ProvenanceValue<String>.missing();
    var period = const ProvenanceValue<String>.missing();
    var classroom = const ProvenanceValue<String>.missing();
    var examInfo = const ProvenanceValue<String>.missing();
    var marks = const ProvenanceValue<String>.missing();

    for (final line in lines) {
      timetable = timetable.isMissing
          ? _labelValue(line, re(r'(?:timetable|time\s*table)\s*[:.]?\s+(\S.+)'))
          : timetable;
      period = period.isMissing
          ? _labelValue(line, re(r'period\s*[:.]?\s+(\S+)'))
          : period;
      classroom = classroom.isMissing
          ? _labelValue(
              line,
              re(r'(?:class\s*room|room\s*(?:no\.?|number)?)\s*[:.]?\s+(\S.+)'),
            )
          : classroom;
      examInfo = examInfo.isMissing
          ? _labelValue(line, re(r'(?:exam|assessment|internal|test)\s*[:.]?\s+(\S.+)'))
          : examInfo;
      marks = marks.isMissing
          ? _labelValue(line, re(r'(?:mark|grade|score)\s*[:.]?\s+(\S.+)'))
          : marks;
    }
    return ParsedOptionalInfo(
      timetable: timetable,
      period: period,
      classroom: classroom,
      examInfo: examInfo,
      marks: marks,
    );
  }
}