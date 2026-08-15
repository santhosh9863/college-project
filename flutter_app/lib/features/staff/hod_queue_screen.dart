import 'package:flutter/material.dart';

import '../../core/utils/relative_time.dart';
import '../reports/data/models/report.dart';
import '../reports/data/models/report_priority.dart';
import '../reports/widgets/report_detail_widgets.dart';
import 'hod_detail_screen.dart';
import 'hod_queue_controller.dart';

/// HOD department queue: the D1-scoped routed reports with status/search
/// filters. Tapping a report opens the staff detail with lifecycle actions.
class HodQueueScreen extends StatelessWidget {
  const HodQueueScreen({super.key, required this.controller});

  final HodQueueController controller;

  Future<void> _openDetail(BuildContext context, Report report) async {
    final detailController = controller.detailControllerFor(report.id);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HodDetailScreen(controller: detailController),
      ),
    );
    detailController.dispose();
    controller.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          children: [
            _FilterBar(controller: controller),
            Expanded(
              child: switch (controller.status) {
                HodQueueStatus.loading =>
                  const Center(child: CircularProgressIndicator()),
                HodQueueStatus.error => _ErrorBody(
                    onRetry: controller.load,
                  ),
                HodQueueStatus.ready => _buildList(context),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(BuildContext context) {
    final reports = controller.reports;
    if (reports.isEmpty) {
      return _EmptyBody(
        message: controller.hasActiveFilters
            ? 'No reports match the current filters.'
            : 'No department reports right now.\nNew reports routed to your department appear here.',
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final report = reports[index];
          return _ReportTile(
            report: report,
            onTap: () => _openDetail(context, report),
          );
        },
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final HodQueueController controller;

  static const _statusOptions = [
    ('all', 'All'),
    ('pending', 'Pending'),
    ('under_review', 'Review'),
    ('in_progress', 'In progress'),
    ('resolved', 'Resolved'),
    ('rejected', 'Rejected'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: controller.setSearch,
            decoration: const InputDecoration(
              hintText: 'Search department reports',
              isDense: true,
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (value, label) in _statusOptions)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(label),
                      selected: controller.statusFilter == value,
                      onSelected: (_) => controller.setStatusFilter(value),
                    ),
                  ),
                if (controller.hasActiveFilters)
                  TextButton.icon(
                    onPressed: controller.clearFilters,
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('Clear'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  const _ReportTile({required this.report, required this.onTap});

  final Report report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      report.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ReportStatusBadge(status: report.status),
                ],
              ),
              if (report.description.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  report.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Icon(
                    switch (report.priority) {
                      ReportPriority.high || ReportPriority.critical =>
                        Icons.arrow_upward,
                      ReportPriority.low => Icons.arrow_downward,
                      _ => Icons.remove,
                    },
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  Text(
                    report.categoryName,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  Text(
                    '·',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  Text(
                    relativeTime(report.createdAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
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
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load the department queue.",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
