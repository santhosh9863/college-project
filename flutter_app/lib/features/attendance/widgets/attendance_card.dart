import 'package:flutter/material.dart';

import '../attendance_controller.dart';
import '../data/attendance_summary.dart';
import '../import/models/parsed_linways_snapshot.dart';

/// Dashboard card showing attendance. Two clearly labelled sources:
/// - **LIVE** — overall percentage fetched from Linways (MVP: percentage
///   only, per locked decision 4).
/// - **IMPORT** — a confirmed screenshot-derived snapshot shown above the
///   live value; the student can switch back at any time.
class AttendanceCard extends StatelessWidget {
  const AttendanceCard({
    super.key,
    required this.controller,
    required this.onRefresh,
    this.onReSignIn,
    this.onImportScreenshot,
  });

  final AttendanceController controller;
  final Future<void> Function() onRefresh;

  /// Called when the stored Linways session was rejected and the user chooses
  /// to sign in again (full logout + re-login).
  final VoidCallback? onReSignIn;

  /// Opens the screenshot import flow. `null` hides the import button.
  final VoidCallback? onImportScreenshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (controller.importedSnapshot != null) ...[
              _ImportedSummary(
                snapshot: controller.importedSnapshot!,
                onUseLive: controller.clearImported,
              ),
              const SizedBox(height: 16),
            ],
            switch (controller.status) {
              AttendanceStatus.loading => const _LoadingBody(),
              AttendanceStatus.ready ||
              AttendanceStatus.stale => _SummaryBody(
                  summary: controller.summary,
                  isStale: controller.status == AttendanceStatus.stale,
                  onRefresh: onRefresh,
                ),
              AttendanceStatus.unavailable => _UnavailableBody(
                  sessionExpired: controller.sessionExpired,
                  onRefresh: onRefresh,
                  onReSignIn: onReSignIn,
                ),
            },
            if (onImportScreenshot != null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: onImportScreenshot,
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Import Linways Screenshot'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Screenshot-derived attendance (IMPORT source) — memory only.
class _ImportedSummary extends StatelessWidget {
  const _ImportedSummary({required this.snapshot, required this.onUseLive});

  final ParsedLinwaysSnapshot snapshot;
  final VoidCallback onUseLive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overall = snapshot.overall;
    final percentage = overall.percentage.value;
    final counts =
        overall.conducted.isPresent && overall.attended.isPresent
            ? '${overall.attended.value} of ${overall.conducted.value} classes attended'
            : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.screenshot_monitor_outlined,
                  size: 18, color: theme.colorScheme.onSecondaryContainer),
              const SizedBox(width: 6),
              Text(
                'Imported attendance',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'IMPORT',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (percentage != null)
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: _percentageColor(theme, percentage),
              ),
            ),
          if (counts != null)
            Text(
              counts,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          if (snapshot.attendanceDate.isPresent)
            Text(
              'As of ${snapshot.attendanceDate.value}',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
            ),
          Text(
            'Read from a screenshot — reviewed before use. Not saved.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onUseLive,
              child: const Text('Use live attendance'),
            ),
          ),
        ],
      ),
    );
  }

  static Color _percentageColor(ThemeData theme, double percentage) {
    if (percentage < 75) return theme.colorScheme.error;
    if (percentage < 85) return Colors.orange.shade800;
    return Colors.green.shade700;
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
