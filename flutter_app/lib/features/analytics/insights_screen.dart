import 'package:flutter/material.dart';

import '../reports/data/models/report_priority.dart';
import '../reports/data/models/report_status.dart';
import 'analytics_controller.dart';
import 'data/analytics_overview.dart';

/// Insights dashboard. The data shown is whatever the server-side
/// `analytics_overview` RPC computed for THIS caller (D6) — students see
/// their own reports, staff see their department scope, admin sees all.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.controller});

  final AnalyticsController controller;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          switch (widget.controller.status) {
            case AnalyticsStatus.loading:
              return const Center(child: CircularProgressIndicator());
            case AnalyticsStatus.error:
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Could not load insights.'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: widget.controller.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            case AnalyticsStatus.ready:
              final overview = widget.controller.overview;
              if (overview == null) return const SizedBox.shrink();
              if (overview.totalReports == 0) {
                return const Center(
                  child: Text('No report data to show yet.'),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SummaryCard(overview: overview),
                  const SizedBox(height: 12),
                  _BreakdownCard(
                    title: 'By status',
                    counts: overview.byStatus,
                    label: (key) => ReportStatus.fromApi(key).label,
                  ),
                  const SizedBox(height: 12),
                  _BreakdownCard(
                    title: 'By priority',
                    counts: overview.byPriority,
                    label: (key) => ReportPriority.fromApi(key).label,
                  ),
                  const SizedBox(height: 12),
                  _BreakdownCard(
                    title: 'By category',
                    counts: overview.byCategory,
                    label: (key) => key,
                  ),
                ],
              );
          }
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.overview});

  final AnalyticsOverview overview;

  @override
  Widget build(BuildContext context) {
    final avg = overview.resolvedAvgDays;
    final avgLabel = avg == null ? '—' : avg.toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _SummaryTile(
                label: 'Total reports',
                value: '${overview.totalReports}',
              ),
            ),
            Expanded(
              child: _SummaryTile(
                label: 'Open',
                value: '${overview.openReports}',
              ),
            ),
            Expanded(
              child: _SummaryTile(
                label: 'Avg. days to resolve',
                value: avgLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
      ],
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.title,
    required this.counts,
    required this.label,
  });

  final String title;
  final Map<String, int> counts;
  final String Function(String key) label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final entry in entries) ...[
              Row(
                children: [
                  Expanded(child: Text(label(entry.key))),
                  Text('${entry.value}'),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : entry.value / total,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}