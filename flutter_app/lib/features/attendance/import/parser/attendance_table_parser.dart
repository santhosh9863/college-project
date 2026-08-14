import '../models/parsed_linways_snapshot.dart';
import '../models/provenance.dart';
import '../models/validation_issue.dart';
import 'ocr_text.dart';
import 'pattern_helpers.dart';

/// Parses subject-wise attendance rows from OCR lines.
///
/// Text-based only: a candidate row is a line with at least two standalone
/// integers and some text, that is not a label/header/date line. Column
/// semantics come from a visible header when present; otherwise the trailing
/// integers are assumed to be conducted → attended → absent (plus a `%`
/// percentage when present).
class AttendanceTableParser {
  const AttendanceTableParser();

  static const Set<String> _headerColumnWords = {
    'subject',
    'code',
    'faculty',
    'conducted',
    'attended',
    'absent',
    'present',
    'percentage',
    '%',
    'total',
  };

  static const Set<String> _excludedLeadingWords = {
    'total',
    'overall',
    'grand',
    'summary',
    'result',
  };

  /// Parses subject rows from [lines], appending issues to [warnings].
  List<ParsedSubjectAttendance> parse(
    List<OcrLine> lines, {
    required List<ValidationIssue> warnings,
  }) {
    final columns = _findHeaderColumns(lines);
    final seen = <String>{};
    final rows = <ParsedSubjectAttendance>[];

    for (final line in lines) {
      final row = _parseRow(line, columns, warnings);
      if (row == null) continue;
      if (!row.isValid) continue;

      final key = row.dedupeKey;
      if (key.isNotEmpty && !seen.add(key)) {
        warnings.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'duplicateSubjectRow',
          message:
              'Duplicate subject row "${row.name.value}" was ignored.',
          field: 'subjects',
        ));
        continue;
      }
      rows.add(row);
    }
    return rows;
  }

  /// Column index map for header words, e.g. {conducted: 0, attended: 1}.
  Map<String, int>? _findHeaderColumns(List<OcrLine> lines) {
    for (final line in lines) {
      final tokens = line.dePiped.toLowerCase().split(' ');
      final hits = tokens.where(_headerColumnWords.contains).toList();
      if (hits.length >= 3 && hits.contains('subject')) {
        return {for (var i = 0; i < tokens.length; i++) tokens[i]: i};
      }
    }
    return null;
  }

  ParsedSubjectAttendance? _parseRow(
    OcrLine line,
    Map<String, int>? columns,
    List<ValidationIssue> warnings,
  ) {
    if (_isHeaderLine(line) || _isLabelLine(line)) return null;

    final dePiped = line.dePiped;
    final percentage = TextPatterns.percentageIn(dePiped);
    // Strip percentage tokens before integer extraction so `80.0%` never
    // leaks an extra integer that shifts column mapping.
    final numericText =
        percentage == null ? dePiped : dePiped.replaceAll(TextPatterns.pctToken, ' ');
    final numbers = TextPatterns.intsIn(numericText);

    final textPart = _textBeforeNumbers(dePiped, numbers.length);
    if (textPart.isEmpty) return null;
    if (numbers.length < 2 && percentage == null) return null;
    if (_excludedLeadingWords.contains(textPart.toLowerCase().split(' ').first)) {
      return null;
    }

    // Pull subject code / faculty out of the text part (no guessing — only
    // tokens that are clearly codes or faculty titles).
    String? code;
    final codeMatch = TextPatterns.codeToken.firstMatch(textPart);
    if (codeMatch != null) {
      code = codeMatch.group(0)!;
    }
    String? faculty;
    final facultyMatch = TextPatterns.facultyTitle.firstMatch(textPart);
    if (facultyMatch != null) {
      final start = textPart.indexOf(facultyMatch.group(0)!);
      final remainder = textPart.substring(start).trim();
      faculty = remainder.isNotEmpty ? remainder : null;
    }
    var name = _cleanSubjectName(textPart, code, faculty);

    // Column semantics come from the visible header when present: it selects
    // which of conducted/attended/absent/percentage the row actually reports.
    // The header column order is not used for indexing — percentage tokens are
    // already stripped from [numbers], so the row's integers always appear
    // positionally (conducted → attended → absent) in column order.
    final declared = columns == null
        ? const ['conducted', 'attended', 'absent', 'percentage']
        : const ['conducted', 'attended', 'absent', 'percentage']
            .where(columns.containsKey)
            .toList();

    var conducted = _valueAt(numbers, declared, 'conducted');
    var attended = _valueAt(numbers, declared, 'attended');
    var absent = _valueAt(numbers, declared, 'absent');
    var pct = percentage ?? _percentageFromColumn(numbers, declared);

    if (conducted == null && attended == null && pct == null) return null;

    // Suspicious OCR tokens (O/I/L vs 0/1) make numeric attribution unsafe —
    // the row's numbers are treated as missing, never "corrected" or shifted.
    if (TextPatterns.isSuspiciousNumeric(dePiped)) {
      warnings.add(ValidationIssue(
        severity: ValidationSeverity.warning,
        code: 'suspiciousOcrNumber',
        message:
            '"$name" contains an ambiguous number (O/I/L vs 0/1) — that row\'s values were not read.',
        field: 'subjects',
      ));
      conducted = null;
      attended = null;
      absent = null;
      pct = null;
      name = TextPatterns.suspiciousNumericToken
          .allMatches(name)
          .fold(name, (n, m) => n.replaceFirst(m.group(0)!, ' '))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    // Derive absent from visible counts (math-supported only).
    if (absent == null && conducted != null && attended != null) {
      absent = conducted - attended;
    }

    if (conducted != null && attended != null && attended > conducted) {
      warnings.add(ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'invalidSubjectCounts',
        message: 'Attendance counts are invalid for "$name" (attended > conducted).',
        field: 'subjects',
      ));
    }
    if (absent != null && conducted != null && absent > conducted) {
      warnings.add(ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'invalidSubjectCounts',
        message: 'Attendance counts are invalid for "$name" (absent > conducted).',
        field: 'subjects',
      ));
    }
    if (pct != null && conducted != null && attended != null) {
      final calculated = attended / conducted * 100;
      if ((pct - calculated).abs() > 0.05) {
        warnings.add(ValidationIssue(
          severity: ValidationSeverity.warning,
          code: 'subjectPercentageMismatch',
          message:
              '"$name" shows $pct%, but the counts calculate ${calculated.toStringAsFixed(1)}%.',
          field: 'subjects',
        ));
      }
    }
    if (pct != null && (pct < 0 || pct > 100)) {
      warnings.add(ValidationIssue(
        severity: ValidationSeverity.error,
        code: 'invalidPercentage',
        message: 'Percentage for "$name" is outside 0–100.',
        field: 'subjects',
      ));
    }

    return ParsedSubjectAttendance(
      name: ProvenanceValue.extracted(name),
      code: code == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(code),
      faculty: faculty == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(faculty),
      conducted: conducted == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(conducted),
      attended: attended == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(attended),
      absent: absent == null
          ? const ProvenanceValue.missing()
          : (numbers.length >= 3 || columns?.containsKey('absent') == true
              ? ProvenanceValue.extracted(absent)
              : ProvenanceValue.derived(absent)),
      percentage: pct == null
          ? const ProvenanceValue.missing()
          : ProvenanceValue.extracted(pct),
    );
  }

  /// Value for [column] read positionally from the row's integers. [declared]
  /// holds the numeric columns the screenshot actually reports, in standard
  /// order; a column the header never declared is never guessed.
  static int? _valueAt(List<int> numbers, List<String> declared, String column) {
    final index = declared.indexOf(column);
    return index >= 0 && index < numbers.length ? numbers[index] : null;
  }

  /// Plain-integer percentage (no `%` sign, e.g. `80`) in the percentage
  /// column. A visible `%` token is always preferred and never duplicated.
  static double? _percentageFromColumn(List<int> numbers, List<String> declared) {
    final index = declared.indexOf('percentage');
    if (index < 0 || index >= numbers.length) return null;
    return numbers[index].toDouble();
  }

  static bool _isHeaderLine(OcrLine line) {
    final tokens = line.dePiped.toLowerCase().split(' ');
    final hits = tokens.where(_headerColumnWords.contains).toList();
    return hits.length >= 3;
  }

  static bool _isLabelLine(OcrLine line) {
    final lower = line.lower;
    if (TextPatterns.dateToken.hasMatch(lower)) return true;
    if (lower.contains('conducted') || lower.contains('attended')) return true;
    if (lower.contains('subject') && lower.contains('code')) return true;
    if (lower.contains('attendance percentage') ||
        lower.contains('overall attendance')) {
      return true;
    }
    return RegExp(r'\b(name|register|semester|section|department|batch|academic year|usn)\b')
        .hasMatch(lower);
  }

  /// Text tokens before the first number — the subject name area.
  static String _textBeforeNumbers(String dePiped, int numberCount) {
    final tokens = dePiped.split(' ');
    final result = <String>[];
    for (final token in tokens) {
      if (TextPatterns.intsIn(token).isNotEmpty || TextPatterns.pctToken.hasMatch(token)) {
        break;
      }
      result.add(token);
    }
    return result.join(' ').trim();
  }

  static String _cleanSubjectName(String textPart, String? code, String? faculty) {
    var name = textPart;
    if (code != null) {
      name = name.replaceAll(RegExp(RegExp.escape(code)), ' ').trim();
    }
    if (faculty != null) {
      name = name.replaceAll(RegExp(RegExp.escape(faculty)), ' ').trim();
    }
    name = name.replaceAll(TextPatterns.facultyTitle, ' ').trim();
    return name.replaceAll(RegExp(r'\s+'), ' ');
  }
}