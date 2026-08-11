import 'package:flutter/material.dart';

import '../../core/utils/relative_time.dart';
import 'data/report.dart';
import 'reports_controller.dart';

/// Community reports tab: read-only list of reports visible to the student
/// (RLS-scoped). Creation and lifecycle management arrive in later phases.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.controller});

  final ReportsController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return switch (controller.status) {
          ReportsStatus.loading => const Center(child: CircularProgressIndicator()),
          ReportsStatus.error => _ErrorBody(onRetry: controller.load),
          ReportsStatus.ready => RefreshIndicator(
              onRefresh: controller.load,
              child: controller.reports.isEmpty
                  ? _EmptyBody()
                  : ListView.separated(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: controller.reports.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _ReportTile(report: controller.reports[index]),
                    ),
            ),
        };
      },
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report});

  final Report report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(
          report.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            [
              report.categoryName,
              report.createdAt == null ? null : relativeTime(report.createdAt!),
            ].whereType<String>().join(' · '),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _priorityIcon(report.priority),
              size: 18,
              color: _priorityColor(theme, report.priority),
            ),
            const SizedBox(width: 8),
            _StatusBadge(status: report.status),
          ],
        ),
      ),
    );
  }

  IconData _priorityIcon(String priority) => switch (priority) {
        'high' => Icons.arrow_upward,
        'low' => Icons.arrow_downward,
        _ => Icons.remove,
      };

  Color _priorityColor(ThemeData theme, String priority) => switch (priority) {
        'high' => theme.colorScheme.error,
        'low' => theme.colorScheme.onSurfaceVariant,
        _ => Colors.orange.shade800,
      };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  static const Map<String, (Color, String)> _styles = {
    'pending': (Colors.blueGrey, 'Pending'),
    'under_review': (Colors.blue, 'Under review'),
    'in_progress': (Colors.orange, 'In progress'),
    'resolved': (Colors.green, 'Resolved'),
    'rejected': (Colors.red, 'Rejected'),
    'closed': (Colors.black54, 'Closed'),
  };

  @override
  Widget build(BuildContext context) {
    final (color, label) = _styles[status] ?? (Colors.blueGrey, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(Icons.receipt_long_outlined, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          'No reports yet from your community.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Pull down to refresh.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text("Couldn't load reports.", style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
