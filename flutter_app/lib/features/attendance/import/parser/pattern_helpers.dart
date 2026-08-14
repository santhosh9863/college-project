/// Shared regex/parsing helpers for the screenshot parser.
///
/// All number tokens are required to be standalone (not glued to letters) so
/// subject codes like `CS201` never leak digits into counts.
class TextPatterns {
  TextPatterns._();

  /// Standalone integer token, e.g. `40`, `32` — never a digit glued to a
  /// letter such as the `201` in `CS201`.
  static final RegExp intToken = RegExp(r'(?<![\w])\d{1,4}(?![\w])');

  /// Percentage value with optional decimals, e.g. `89.11%`, `80 %`.
  static final RegExp pctToken = RegExp(r'\b(\d{1,3}(?:\.\d{1,2})?)\s*%');

  /// Subject-code-like token, e.g. `CS201`, `21CS51`.
  static final RegExp codeToken = RegExp(r'\b[A-Za-z]{2,5}\d{3,4}\b');

  /// Faculty title token.
  static final RegExp facultyTitle = RegExp(
    r'\b(?:prof\.?|dr\.?|mr\.?|ms\.?|mrs\.?|faculty)\b',
    caseSensitive: false,
  );

  /// Date-like token: `DD/MM/YYYY`, `DD-MM-YY`, `YYYY-MM-DD`, `12 Aug 2026`.
  static final RegExp dateToken = RegExp(
    r'\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b'
    r'|\b\d{4}-\d{2}-\d{2}\b'
    r'|\b\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{2,4}\b',
    caseSensitive: false,
  );

  /// Academic-year range, e.g. `2024-2025`, `2024 – 25`.
  static final RegExp academicYearToken = RegExp(
    r'\b((?:19|20)\d{2}\s*[-–]\s*\d{2,4})\b',
  );

  /// Standalone integers in [text] (see [intToken]).
  static List<int> intsIn(String text) => [
        for (final match in intToken.allMatches(text)) int.parse(match.group(0)!),
      ];

  /// First percentage value in [text], or `null`.
  static double? percentageIn(String text) {
    final match = pctToken.firstMatch(text);
    return match == null ? null : double.parse(match.group(1)!);
  }

  /// Whether [text] contains any numeric value at all.
  static bool hasAnyNumber(String text) => intToken.hasMatch(text);

  /// OCR-noise token: a digit glued to an O/I/L lookalike letter, e.g. `4O`,
  /// `8I`, `0L`. Clean words like `BCA` are never flagged.
  static final RegExp suspiciousNumericToken = RegExp(r'\b\d*[OoIl]\d*\b');

  /// True when a labeled value looks like OCR noise (letters mixed into a
  /// number), e.g. `Conducted 8O` or `80.O %`.
  static bool isSuspiciousNumeric(String text) =>
      suspiciousNumericToken.hasMatch(text);
}
