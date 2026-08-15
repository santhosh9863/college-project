/// Report priority. Matches the `priority` enum in the database
/// (low/medium/high/critical).
enum ReportPriority {
  low('low', 'Low'),
  medium('medium', 'Medium'),
  high('high', 'High'),
  critical('critical', 'Critical'),
  unknown('', 'Unknown');

  const ReportPriority(this.apiValue, this.label);

  /// Value stored in the database.
  final String apiValue;

  /// User-facing label.
  final String label;

  static ReportPriority fromApi(String? value) => values.firstWhere(
        (priority) => priority.apiValue == value,
        orElse: () => ReportPriority.unknown,
      );
}
