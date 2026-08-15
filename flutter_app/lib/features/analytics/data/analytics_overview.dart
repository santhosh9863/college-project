/// Aggregated statistics over exactly the reports the caller may see
/// (computed server-side by the view-gated `analytics_overview` RPC, D6).
class AnalyticsOverview {
  const AnalyticsOverview({
    required this.totalReports,
    required this.openReports,
    required this.byStatus,
    required this.byCategory,
    required this.byPriority,
    this.resolvedAvgDays,
  });

  factory AnalyticsOverview.fromJson(Map<String, dynamic> json) {
    Map<String, int> parseCounts(dynamic value) {
      final source = value is Map<String, dynamic>
          ? value
          : (value is Map ? Map<String, dynamic>.from(value) : const <String, dynamic>{});
      return source.map((key, count) => MapEntry(key, (count as num).toInt()));
    }

    final avg = json['resolved_avg_days'];
    return AnalyticsOverview(
      totalReports: (json['total_reports'] as num?)?.toInt() ?? 0,
      openReports: (json['open_reports'] as num?)?.toInt() ?? 0,
      byStatus: parseCounts(json['by_status']),
      byCategory: parseCounts(json['by_category']),
      byPriority: parseCounts(json['by_priority']),
      resolvedAvgDays: avg is num ? avg.toDouble() : null,
    );
  }

  final int totalReports;
  final int openReports;
  final Map<String, int> byStatus;
  final Map<String, int> byCategory;
  final Map<String, int> byPriority;
  final double? resolvedAvgDays;
}