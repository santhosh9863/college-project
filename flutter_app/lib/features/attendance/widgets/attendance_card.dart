import 'package:flutter/material.dart';

import '../attendance_controller.dart';
import '../data/attendance_summary.dart';

/// Dashboard card showing the overall attendance percentage fetched live from
/// Linways (MVP: percentage only, per locked decision 4).
class AttendanceCard extends StatelessWidget {
  const AttendanceCard({
    super.key,
    required this.controller,
    required this.onRefresh,
    this.onReSignIn,
  });

  final AttendanceController controller;
  final Future<void> Function() onRefresh;

  /// Called when the stored Linways session was rejected and the user chooses
  /// to sign in again (full logout + re-login).
  final VoidCallback? onReSignIn;

  @override
  Widget build(BuildContext context) {
    final summary = controller.summary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: switch (controller.status) {
          AttendanceStatus.loading => const _LoadingBody(),
          AttendanceStatus.ready ||
          AttendanceStatus.stale => _SummaryBody(
              summary: summary,
              isStale: controller.status == AttendanceStatus.stale,
              onRefresh: onRefresh,
            ),
          AttendanceStatus.unavailable => _UnavailableBody(
              sessionExpired: controller.sessionExpired,
              onRefresh: onRefresh,
              onReSignIn: onReSignIn,
            ),
        },
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attendance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.summary,
    required this.isStale,
    required this.onRefresh,
  });

  final AttendanceSummary? summary;
  final bool isStale;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentage = summary?.attendancePercentage;
    final total = summary?.totalHours ?? 0;
    final attended = summary?.attendedHours ?? 0;
    final unit = (summary?.isHourWiseEnabled ?? false) ? 'hours' : 'classes';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Attendance', style: theme.textTheme.titleMedium),
            const Spacer(),
            if (isStale)
              Tooltip(
                message: 'College server unreachable — showing the last known value.',
                child: Icon(
                  Icons.cloud_off_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              percentage == null ? '—' : percentage.toStringAsFixed(1),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _percentageColor(theme, percentage),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 4),
              child: Text('%', style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          total == 0 ? 'Overall attendance' : '$attended of $total $unit attended',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Color _percentageColor(ThemeData theme, double? percentage) {
    if (percentage == null) return theme.colorScheme.onSurface;
    if (percentage < 75) return theme.colorScheme.error;
    if (percentage < 85) return Colors.orange.shade800;
    return Colors.green.shade700;
  }
}

class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody({
    required this.sessionExpired,
    required this.onRefresh,
    this.onReSignIn,
  });

  final bool sessionExpired;
  final Future<void> Function() onRefresh;
  final VoidCallback? onReSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Attendance', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (sessionExpired) ...[
          Text(
            'Your college session has expired.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Sign in again to refresh your attendance.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onReSignIn, child: const Text('Sign in again')),
        ] else ...[
          Text(
            "Couldn't reach the college server.",
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(onPressed: onRefresh, child: const Text('Retry')),
        ],
      ],
    );
  }
}
