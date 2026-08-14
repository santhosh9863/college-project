/// Provenance of a parsed field: how the value was obtained.
///
/// No value is ever guessed. A field is either read from the OCR text
/// ([extracted]), computed from visible values ([derived]), or not present in
/// the screenshot ([missing]).
enum ExtractionSource {
  extracted,
  derived,
  missing;

  /// Display label used in the preview UI.
  String get label => switch (this) {
        ExtractionSource.extracted => 'EXTRACTED',
        ExtractionSource.derived => 'CALCULATED',
        ExtractionSource.missing => 'UNAVAILABLE',
      };
}

/// A parsed value together with its provenance.
///
/// [value] is `null` when [source] is [ExtractionSource.missing].
class ProvenanceValue<T> {
  const ProvenanceValue.extracted(T this.value, {this.confidence})
      : source = ExtractionSource.extracted;

  const ProvenanceValue.derived(T this.value)
      : source = ExtractionSource.derived,
        confidence = null;

  const ProvenanceValue.missing()
      : value = null,
        source = ExtractionSource.missing,
        confidence = null;

  final T? value;
  final ExtractionSource source;

  /// Optional OCR confidence in 0..1 (extracted fields only).
  final double? confidence;

  bool get isMissing => source == ExtractionSource.missing;
  bool get isPresent => !isMissing;

  @override
  bool operator ==(Object other) =>
      other is ProvenanceValue<T> &&
      other.source == source &&
      other.value == value &&
      other.confidence == confidence;

  @override
  int get hashCode => Object.hash(source, value, confidence);

  @override
  String toString() => '$source($value)';
}