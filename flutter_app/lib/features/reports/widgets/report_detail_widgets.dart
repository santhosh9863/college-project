import 'package:flutter/material.dart';

import '../../../core/utils/relative_time.dart';
import '../data/models/evidence_file.dart';
import '../data/models/report.dart';
import '../data/models/report_activity_item.dart';
import '../data/models/report_comment.dart';
import '../data/models/report_priority.dart';
import '../data/models/report_status.dart';
import '../data/reports_repository.dart';

/// Shared detail-building widgets used by the student detail screen and the
/// staff (HOD) detail screen. All reads are RLS-scoped; the widgets only
/// render what the database already allowed.

class ReportHeaderCard extends StatelessWidget {
  const ReportHeaderCard({
    super.key,
    required this.report,
    this.assigneeId,
    this.authorLabel,
  });

  final Report report;
  final String? assigneeId;

  /// Author display label; defaults to the student phrasing.
  final String? authorLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ReportStatusBadge(status: report.status),
                ReportPriorityBadge(priority: report.priority),
                if (assigneeId != null)
                  const ReportLabelBadge(
                    icon: Icons.person_pin_circle_outlined,
                    label: 'Assigned to staff',
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              report.title,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              [
                report.categoryName,
                authorLabel ?? (report.isMine ? 'You' : 'Community member'),
              ].join(' · '),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Text(
              [
                'Reported ${relativeTime(report.createdAt)}',
                if (report.updatedAt != null &&
                    report.updatedAt != report.createdAt)
                  'Updated ${relativeTime(report.updatedAt!)}',
              ].join(' · '),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class ReportActivityRow extends StatelessWidget {
  const ReportActivityRow({super.key, required this.item});

  final ReportActivityItem item;

  IconData _icon() => switch (item.activityType) {
        'created' => Icons.add_circle_outline,
        'status_change' => Icons.sync_alt,
        'assigned' => Icons.person_add_alt,
        'unassigned' => Icons.person_remove_outlined,
        'soft_deleted' => Icons.delete_outline,
        'restored' => Icons.restore,
        _ => Icons.history,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(_icon(), size: 18, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Text(item.displayMessage, style: theme.textTheme.bodyMedium),
        ),
        Text(
          relativeTime(item.createdAt),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}

/// Evidence thumbnail with signed-URL loading and fullscreen preview.
/// [signedUrlFor] resolves the short-lived URL for one private file.
class ReportEvidenceTile extends StatefulWidget {
  const ReportEvidenceTile({
    super.key,
    required this.signedUrlFor,
    required this.file,
  });

  final Future<String> Function(EvidenceFile file) signedUrlFor;
  final EvidenceFile file;

  @override
  State<ReportEvidenceTile> createState() => _ReportEvidenceTileState();
}

class _ReportEvidenceTileState extends State<ReportEvidenceTile> {
  late Future<String> _signedUrl;

  @override
  void initState() {
    super.initState();
    _signedUrl = widget.signedUrlFor(widget.file);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = widget.file;
    final isImage = file.fileType.startsWith('image/');

    Widget content;
    if (!isImage) {
      content = Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.picture_as_pdf, size: 28),
          ],
        ),
      );
    } else {
      content = FutureBuilder<String>(
        future: _signedUrl,
        builder: (context, snapshot) {
          if (snapshot.hasError || !snapshot.hasData) {
            return Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            );
          }
          return Image.network(
            snapshot.data!,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (_, _, _) => Container(
              color: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          );
        },
      );
    }

    return InkWell(
      onTap: isImage
          ? () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                child: FutureBuilder<String>(
                  future: _signedUrl,
                  builder: (context, snapshot) {
                    if (snapshot.hasError || !snapshot.hasData) {
                      return const SizedBox(
                        height: 200,
                        child: Center(child: Text('Preview unavailable')),
                      );
                    }
                    return InteractiveViewer(
                      child: Image.network(snapshot.data!),
                    );
                  },
                ),
              ),
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(aspectRatio: 1, child: content),
      ),
    );
  }
}

class ReportCommentRow extends StatelessWidget {
  const ReportCommentRow({
    super.key,
    required this.comment,
    required this.onDelete,
  });

  final ReportComment comment;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.isMine ? 'You' : 'Community member',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    relativeTime(comment.createdAt),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(comment.message, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        if (comment.isMine)
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: 'Delete comment',
          ),
      ],
    );
  }
}

class ReportStatusBadge extends StatelessWidget {
  const ReportStatusBadge({super.key, required this.status});

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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ReportPriorityBadge extends StatelessWidget {
  const ReportPriorityBadge({super.key, required this.priority});

  final ReportPriority priority;

  @override
  Widget build(BuildContext context) {
    return ReportLabelBadge(
      icon: switch (priority) {
        ReportPriority.high || ReportPriority.critical =>
          Icons.arrow_upward,
        ReportPriority.low => Icons.arrow_downward,
        _ => Icons.remove,
      },
      label: '${priority.label} priority',
    );
  }
}

class ReportLabelBadge extends StatelessWidget {
  const ReportLabelBadge({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSecondaryContainer,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ReportDetailErrorBody extends StatelessWidget {
  const ReportDetailErrorBody({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notFound = error is ReportNotFoundException;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              notFound ? Icons.visibility_off_outlined : Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              notFound
                  ? "This report is no longer visible to you."
                  : "Couldn't load the report.",
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (!notFound) ...[
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
