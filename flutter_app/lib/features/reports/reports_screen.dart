import 'package:flutter/material.dart';

import '../../core/utils/relative_time.dart';
import '../../data/models/community.dart';
import '../../data/models/profile.dart';
import 'create_report_screen.dart';
import 'data/models/report.dart';
import 'data/models/report_priority.dart';
import 'data/models/report_status.dart';
import 'report_detail_screen.dart';
import 'reports_controller.dart';

/// Community reports tab: RLS-scoped list with status/category/priority
/// filters, title search and own-reports view. Tapping a report opens the
/// detail screen; the button opens the create flow.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({
    super.key,
    required this.controller,
    this.profile,
    this.community,
  });

  final ReportsController controller;

  /// Authenticated identity snapshots passed through to the create flow
  /// (never user input).
  final Profile? profile;
  final Community? community;

  Future<void> _openCreate(BuildContext context) async {
    final created = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => CreateReportScreen(
          controller: controller.createReportController(
            profile: profile,
            community: community,
          ),
        ),
      ),
    );
    if (created != null) await controller.load();
  }

  Future<void> _openDetail(BuildContext context, Report report) async {
    await _pushDetail(context, report.id);
    await controller.load();
  }

  Future<void> _pushDetail(BuildContext context, String reportId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(
          controller: controller.detailControllerFor(reportId),
          onOpenReport: (id) => _pushDetail(context, id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Stack(
          children: [
            Column(
              children: [
                _FilterBar(controller: controller),
                Expanded(
                  child: switch (controller.status) {
                    ReportsStatus.loading =>
                      const Center(child: CircularProgressIndicator()),
                    ReportsStatus.error =>
                      _ErrorBody(onRetry: controller.load),
                    ReportsStatus.ready => RefreshIndicator(
                        onRefresh: controller.load,
                        child: controller.reports.isEmpty
                            ? _EmptyBody(
                                hasActiveFilters: controller.hasActiveFilters,
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 88),
                                itemCount: controller.reports.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  final report = controller.reports[index];
                                  return _ReportTile(
                                    report: report,
                                    onTap: () => _openDetail(context, report),
                                  );
                                },
                              ),
                      ),
                  },
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton.extended(
                onPressed: () => _openCreate(context),
                icon: const Icon(Icons.add),
                label: const Text('New report'),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});

  final ReportsController controller;

  static const List<ReportStatus> _statusOptions = [
    ReportStatus.pending,
    ReportStatus.underReview,
    ReportStatus.inProgress,
    ReportStatus.resolved,
    ReportStatus.rejected,
    ReportStatus.closed,
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            onChanged: controller.setSearch,
            decoration: InputDecoration(
              hintText: 'Search reports',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: controller.search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => controller.setSearch(''),
                    ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusChip(
                  label: 'All',
                  selected: controller.statusFilter == 'all',
                  onSelected: () => controller.setStatusFilter('all'),
                ),
                for (final status in _statusOptions) ...[
                  const SizedBox(width: 8),
                  _StatusChip(
                    label: status.label,
                    selected: controller.statusFilter == status.apiValue,
                    onSelected: () =>
                        controller.setStatusFilter(status.apiValue),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final priority in ReportPriority.values) ...[
                  if (priority != ReportPriority.unknown) ...[
                    if (priority != ReportPriority.low)
                      const SizedBox(width: 8),
                    _StatusChip(
                      label: priority.label,
                      selected: controller.priority == priority.apiValue,
                      onSelected: () => controller.setPriorityFilter(
                        controller.priority == priority.apiValue
                            ? null
                            : priority.apiValue,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final categoryField = DropdownButtonFormField<String>(
                initialValue: controller.categoryId,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('All categories'),
                  ),
                  for (final category in controller.categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) =>
                    controller.setCategoryFilter(value),
              );
              final mineChip = FilterChip(
                label: const Text('My reports'),
                selected: controller.mineOnly,
                onSelected: controller.setMineOnly,
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: categoryField,
                    ),
                    const SizedBox(height: 8),
                    mineChip,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: categoryField),
                  const SizedBox(width: 12),
                  mineChip,
                ],
              );
            },
          ),
          if (controller.hasActiveFilters) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: controller.clearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 18),
                label: const Text('Clear filters'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
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
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      report.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _priorityIcon(report.priority),
                    size: 18,
                    color: _priorityColor(theme, report.priority),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status: report.status),
                ],
              ),
              if (report.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  report.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.thumb_up_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${report.supportCount}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      [
                        report.categoryName,
                        report.isMine ? 'You' : 'Community member',
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
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

  IconData _priorityIcon(ReportPriority priority) => switch (priority) {
        ReportPriority.high => Icons.arrow_upward,
        ReportPriority.critical => Icons.arrow_upward,
        ReportPriority.low => Icons.arrow_downward,
        _ => Icons.remove,
      };

  Color _priorityColor(ThemeData theme, ReportPriority priority) =>
      switch (priority) {
        ReportPriority.high => theme.colorScheme.error,
        ReportPriority.critical => theme.colorScheme.error,
        ReportPriority.low => theme.colorScheme.onSurfaceVariant,
        _ => Colors.orange.shade800,
      };
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final ReportStatus status;

  static const Map<ReportStatus, Color> _styles = {
    ReportStatus.pending: Colors.blueGrey,
    ReportStatus.underReview: Colors.blue,
    ReportStatus.inProgress: Colors.orange,
    ReportStatus.resolved: Colors.green,
    ReportStatus.rejected: Colors.red,
    ReportStatus.closed: Colors.black54,
    ReportStatus.unknown: Colors.blueGrey,
  };

  @override
  Widget build(BuildContext context) {
    final color = _styles[status] ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
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
  const _EmptyBody({required this.hasActiveFilters});

  final bool hasActiveFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Icon(
          hasActiveFilters ? Icons.filter_alt_off : Icons.receipt_long_outlined,
          size: 48,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text(
          hasActiveFilters
              ? 'No reports match your filters.'
              : 'No reports yet from your community.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          hasActiveFilters
              ? 'Clear the filters to see everything.'
              : 'Pull down to refresh.',
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
