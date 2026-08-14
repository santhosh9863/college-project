/// Severity of a validation finding for an imported screenshot.
enum ValidationSeverity { error, warning, info }

/// A single validation finding produced while parsing or validating an
/// imported Linways screenshot.
class ValidationIssue {
  const ValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.field,
  });

  final ValidationSeverity severity;
  final String code;
  final String message;

  /// Dot-path of the affected field, e.g. `overall.percentage`. `null` for
  /// whole-snapshot issues.
  final String? field;

  int get sortRank => switch (severity) {
        ValidationSeverity.error => 0,
        ValidationSeverity.warning => 1,
        ValidationSeverity.info => 2,
      };

  @override
  String toString() => '[$severity] $code: $message ($field)';
}