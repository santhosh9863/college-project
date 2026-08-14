import '../models/parsed_linways_snapshot.dart';
import 'ocr_text.dart';
import 'pattern_helpers.dart';

/// Result of screen type detection.
class ScreenDetection {
  const ScreenDetection(this.type, this.confidence);

  final LinwaysScreenType type;

  /// 0..1 confidence. Low values mean uncertainty; parsing still continues
  /// and the uncertainty is reported (never guessed).
  final double confidence;
}

/// Detects the conceptual Linways screen type from OCR text using labels and
/// structure only — no pixel coordinates.
class LinwaysScreenDetector {
  const LinwaysScreenDetector();

  static final RegExp _overallLabelPattern = _wordBoundaryPattern([
    'attendance percentage',
    'overall attendance',
    'attendance %',
    'overall percentage',
    'attendance percent',
  ]);

  static final RegExp _profileLabelPattern = _wordBoundaryPattern([
    'register no',
    'register number',
    'roll no',
    'roll number',
    'admission no',
    'student id',
    'student number',
    'usn',
    'programme',
    'program',
    'batch',
    'current sem',
    'semester',
    'student name',
    'academic year',
    'department',
    'section',
    'name',
  ]);

  static const Set<String> _subjectHeaderWords = {
    'subject',
    'code',
    'faculty',
    'conducted',
    'attended',
    'absent',
    'present',
    'percentage',
    'classes',
    'total',
  };

  static RegExp _wordBoundaryPattern(List<String> words) => RegExp(
        '\\b(?:${words.join('|')})\\b',
        caseSensitive: false,
      );

  ScreenDetection detect(List<OcrLine> lines) {
    var overallScore = 0;
    var subjectScore = 0;
    var profileScore = 0;

    for (final line in lines) {
      final lower = line.lower;

      // --- Overall attendance ------------------------------------------------
      if (_overallLabelPattern.hasMatch(lower)) {
        overallScore += 3;
      } else if (TextPatterns.percentageIn(lower) != null &&
          _isStandalonePercentageLine(line)) {
        overallScore += 2;
      }

      // --- Student profile ----------------------------------------------------
      if (_profileLabelPattern.hasMatch(lower)) {
        profileScore += 1;
      }

      // --- Subject-wise table -------------------------------------------------
      final headerHits = _subjectHeaderWords.where(lower.contains).length;
      if (headerHits >= 2 && lower.contains('subject')) {
        subjectScore += 3;
      } else if (headerHits >= 3) {
        subjectScore += 2;
      } else if (_looksLikeSubjectRow(line) && !_isLabelLine(line)) {
        subjectScore += 1;
      }
    }

    // Attendance signals take priority over the profile header that usually
    // sits above them; profile is only the answer when no attendance signal
    // exists. Ambiguity lowers the reported confidence.
    final LinwaysScreenType type;
    double confidence;
    if (overallScore > 0) {
      type = LinwaysScreenType.overallAttendance;
      confidence = overallScore / (overallScore + 1);
      if (subjectScore >= overallScore && subjectScore > 0) confidence *= 0.75;
    } else if (subjectScore > 0) {
      type = LinwaysScreenType.subjectWiseAttendance;
      confidence = subjectScore / (subjectScore + 1);
      if (profileScore >= subjectScore) confidence *= 0.75;
    } else if (profileScore > 0) {
      type = LinwaysScreenType.studentProfile;
      confidence = profileScore / (profileScore + 1);
    } else {
      return const ScreenDetection(LinwaysScreenType.unknown, 0);
    }
    return ScreenDetection(type, confidence);
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

  static bool _looksLikeSubjectRow(OcrLine line) {
    final numbers = TextPatterns.intsIn(line.dePiped);
    final hasWord = RegExp(r'[A-Za-z]{2,}').hasMatch(line.dePiped);
    return hasWord && numbers.length >= 2;
  }

  static bool _isLabelLine(OcrLine line) {
    final lower = line.lower;
    if (_profileLabelPattern.hasMatch(lower)) return true;
    if (_overallLabelPattern.hasMatch(lower)) return true;
    if (lower.contains('subject') && lower.contains('conducted')) return true;
    return TextPatterns.dateToken.hasMatch(lower) &&
        RegExp(r'\b(date|as on|as of|updated|report)\b').hasMatch(lower);
  }
}