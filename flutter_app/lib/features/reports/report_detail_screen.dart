import 'package:flutter/material.dart';

import '../../core/utils/relative_time.dart';
import 'data/models/evidence_file.dart';
import 'data/models/report.dart';
import 'data/models/report_activity_item.dart';
import 'data/models/report_comment.dart';
import 'data/models/report_priority.dart';
import 'data/models/report_status.dart';
import 'data/reports_repository.dart';
import 'report_detail_controller.dart';

/// Report detail: status, priority, description, activity timeline, evidence,
/// support, comments and (for the author of a pending report) cancellation.
/// All writes are optimistic in the controller and enforced by RLS.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({super.key, required this.controller});

  final ReportDetailController controller;

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  final _commentController = TextEditingController();

  ReportDetailController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _commentController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleSupport() async {
    try {
      await _controller.toggleSupport();
    } catch (_) {
      _showMessage("Couldn't update support. Please try again.");
    }
  }

  Future<void> _sendComment() async {
    final message = _commentController.text;
    try {
      await _controller.addComment(message);
      _commentController.clear();
    } catch (_) {
      _showMessage("Couldn't post the comment. Please try again.");
    }
  }

  Future<void> _deleteComment(ReportComment comment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _controller.deleteComment(comment.id);
    } catch (_) {
      _showMessage("Couldn't delete the comment.");
    }
  }

  Future<void> _cancelReport() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this report?'),
        content: const Text(
          'The report will be hidden from your community and cannot be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep report'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel report'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final cancelled = await _controller.cancelReport();
    if (!cancelled && mounted) {
      _showMessage("Couldn't cancel the report. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Report')),
      body: switch (controller.status) {
        ReportDetailStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        ReportDetailStatus.error =>
          _ErrorBody(error: controller.error, onRetry: controller.load),
        ReportDetailStatus.ready => _buildDetail(context),
      },
    );
  }

  Widget _buildDetail(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final detail = controller.detail!;
    final report = detail.report;

    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _HeaderCard(report: report, assigneeId: detail.activeAssigneeId),
          if (!report.isMine) ...[
            const SizedBox(height: 12),
            _SupportCard(
              isSupported: controller.isSupported,
              supportCount: controller.supportCount,
              inFlight: controller.supportInFlight,
              onToggle: _toggleSupport,
            ),
          ],
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Description',
              child: Text(report.description,
                  style: theme.textTheme.bodyMedium),
            ),
          ],
          if (detail.activity.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Updates',
              child: Column(
                children: [
                  for (var i = 0; i < detail.activity.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    _ActivityRow(item: detail.activity[i]),
                  ],
                ],
              ),
            ),
          ],
          if (detail.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Evidence',
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: [
                  for (final file in detail.evidence)
                    _EvidenceTile(controller: controller, file: file),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Comments',
            child: Column(
              children: [
                if (detail.comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No comments yet.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < detail.comments.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    _CommentRow(
                      comment: detail.comments[i],
                      onDelete: () => _deleteComment(detail.comments[i]),
                    ),
                  ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Add a comment',
                          isDense: true,
                        ),
                        onSubmitted: (_) => _sendComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: controller.commentInFlight
                          ? null
                          : _sendComment,
                      icon: const Icon(Icons.send),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (report.isMine &&
              report.status == ReportStatus.pending) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: controller.cancelling ? null : _cancelReport,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel my report'),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.report, this.assigneeId});

  final Report report;
  final String? assigneeId;

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
                _StatusBadge(status: report.status),
                _PriorityBadge(priority: report.priority),
                if (assigneeId != null)
                  const _LabelBadge(
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
                report.isMine ? 'You' : 'Community member',
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

class _SupportCard extends StatelessWidget {
  const _SupportCard({
    required this.isSupported,
    required this.supportCount,
    required this.inFlight,
    required this.onToggle,
  });

  final bool isSupported;
  final int supportCount;
  final bool inFlight;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                supportCount == 1
                    ? '1 community member supports this'
                    : '$supportCount community members support this',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            isSupported
                ? FilledButton.tonalIcon(
                    onPressed: inFlight ? null : onToggle,
                    icon: const Icon(Icons.thumb_up),
                    label: const Text('Supported'),
                  )
                : OutlinedButton.icon(
                    onPressed: inFlight ? null : onToggle,
                    icon: const Icon(Icons.thumb_up_outlined),
                    label: const Text('Support'),
                  ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

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

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

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

class _EvidenceTile extends StatefulWidget {
  const _EvidenceTile({required this.controller, required this.file});

  final ReportDetailController controller;
  final EvidenceFile file;

  @override
  State<_EvidenceTile> createState() => _EvidenceTileState();
}

class _EvidenceTileState extends State<_EvidenceTile> {
  late Future<String> _signedUrl;

  @override
  void initState() {
    super.initState();
    _signedUrl = widget.controller.signedUrlFor(widget.file);
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

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.onDelete});

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

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final ReportPriority priority;

  @override
  Widget build(BuildContext context) {
    return _LabelBadge(
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

class _LabelBadge extends StatelessWidget {
  const _LabelBadge({required this.icon, required this.label});

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

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.error, required this.onRetry});

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
