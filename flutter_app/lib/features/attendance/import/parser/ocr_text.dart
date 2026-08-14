/// One normalized OCR line. Parsing is deliberately text-based (labels and
/// structure) — no pixel coordinates, so screenshots from different devices
/// and Linways versions are tolerated.
class OcrLine {
  const OcrLine(this.text);

  final String text;

  /// Trimmed with runs of whitespace collapsed to single spaces.
  String get normalized => text.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// [normalized] lowercased.
  String get lower => normalized.toLowerCase();

  /// The line without table-border characters (`|`).
  String get dePiped => normalized.replaceAll(RegExp(r'\|'), ' ');

  bool get isBlank => text.trim().isEmpty;
}

/// Splits raw OCR output into non-blank [OcrLine]s.
List<OcrLine> splitOcrText(String raw) {
  return [
    for (final line in raw.split(RegExp(r'\r?\n')))
      if (line.trim().isNotEmpty) OcrLine(line),
  ];
}