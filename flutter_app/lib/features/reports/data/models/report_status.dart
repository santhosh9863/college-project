/// Report lifecycle status. Matches the `report_status` enum in the database
/// (pending → under_review → in_progress → resolved → closed, with rejection).
/// Students never change status themselves; the database lifecycle is the only
/// authority.
enum ReportStatus {
  pending('pending', 'Pending'),
  underReview('under_review', 'Under review'),
  inProgress('in_progress', 'In progress'),
  resolved('resolved', 'Resolved'),
  rejected('rejected', 'Rejected'),
  closed('closed', 'Closed'),
  unknown('', 'Unknown');

  const ReportStatus(this.apiValue, this.label);

  /// Value stored in the database.
  final String apiValue;

  /// User-facing label.
  final String label;

  static ReportStatus fromApi(String? value) => values.firstWhere(
        (status) => status.apiValue == value,
        orElse: () => ReportStatus.unknown,
      );
}
