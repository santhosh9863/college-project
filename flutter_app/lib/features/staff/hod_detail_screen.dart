import 'package:flutter/material.dart';

import '../reports/data/models/report_status.dart';
import '../reports/widgets/report_detail_widgets.dart';
import 'hod_detail_controller.dart';

/// Staff (HOD) report detail: full report view plus the lifecycle actions the
/// HOD may take (review/accept, mark in progress, resolve, reject with a
/// reason). Actions are offered per the approved lifecycle matrix; the
/// database remains the enforcement.
class HodDetailScreen extends StatefulWidget {
  const HodDetailScreen({super.key, required this.controller});

  final HodDetailController controller;

  @override
  State<HodDetailScreen> createState() => _HodDetailScreenState();
}

class _HodDetailScreenState extends State<HodDetailScreen> {
  final _commentController = TextEditingController();

  HodDetailController get _controller => widget.controller;

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

  Future<void> _sendComment() async {
    final message = _commentController.text;
    try {
      await _controller.addComment(message);
      _commentController.clear();
    } catch (_) {
      _showMessage("Couldn't post the comment. Please try again.");
    }
  }

  Future<void> _applyStatus(ReportStatus status) async {
    final accepted = await _controller.changeStatus(status);
    if (accepted) {
      _showMessage('Report moved to ${status.label}.');
    } else {
      _showMessage(
        "That status change isn't allowed right now. "
        'Entering in progress requires an active assignment.',
      );
    }
  }

  Future<void> _reject() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => _RejectDialog(),
    );
    if (reason == null) return;
    final accepted = await _controller.reject(reason: reason);
    if (accepted) {
      _showMessage('Report rejected.');
    } else {
      _showMessage("Couldn't reject the report. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Department report')),
      body: switch (controller.status) {
        HodDetailStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        HodDetailStatus.error =>
          ReportDetailErrorBody(error: controller.error, onRetry: controller.load),
        HodDetailStatus.ready => _buildDetail(context),
      },
      bottomNavigationBar: controller.status == HodDetailStatus.ready &&
              controller.availableTransitions.isNotEmpty
          ? _ActionBar(
              controller: controller,
              onStatus: _applyStatus,
              onReject: _reject,
            )
          : null,
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
          ReportHeaderCard(
            report: report,
            assigneeId: detail.activeAssigneeId,
            authorLabel: 'Student report',
          ),
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReportSectionCard(
              title: 'Description',
              child: Text(report.description,
                  style: theme.textTheme.bodyMedium),
            ),
          ],
          if (detail.activity.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReportSectionCard(
              title: 'Updates',
              child: Column(
                children: [
                  for (var i = 0; i < detail.activity.length; i++) ...[
                    if (i > 0) const Divider(height: 16),
                    ReportActivityRow(item: detail.activity[i]),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ReportSectionCard(
            title: 'Evidence',
            child: detail.evidence.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No evidence attached.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [
                      for (final file in detail.evidence)
                        ReportEvidenceTile(
                          signedUrlFor: controller.signedUrlFor,
                          file: file,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
          ReportSectionCard(
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
                    ReportCommentRow(
                      comment: detail.comments[i],
                      onDelete: () {},
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
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Bottom action bar offering the HOD's permitted lifecycle transitions.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.controller,
    required this.onStatus,
    required this.onReject,
  });

  final HodDetailController controller;
  final Future<void> Function(ReportStatus status) onStatus;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final transitions = controller.availableTransitions;
    final others = transitions
        .where((status) => status != ReportStatus.rejected)
        .toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (transitions.contains(ReportStatus.rejected)) ...[
              OutlinedButton.icon(
                onPressed: controller.statusInFlight ? null : onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.block),
                label: const Text('Reject'),
              ),
              if (others.isNotEmpty) const SizedBox(width: 8),
            ],
            for (var i = 0; i < others.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: controller.statusInFlight
                      ? null
                      : () => onStatus(others[i]),
                  icon: Icon(_actionIcon(others[i]), size: 18),
                  label: Text(_actionLabel(others[i])),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _actionLabel(ReportStatus status) => switch (status) {
      ReportStatus.underReview => 'Start review',
      ReportStatus.inProgress => 'Mark in progress',
      ReportStatus.resolved => 'Mark resolved',
      _ => status.label,
    };

IconData _actionIcon(ReportStatus status) => switch (status) {
      ReportStatus.underReview => Icons.rate_review_outlined,
      ReportStatus.inProgress => Icons.play_circle_outline,
      ReportStatus.resolved => Icons.check_circle_outline,
      _ => Icons.arrow_forward,
    };

class _RejectDialog extends StatefulWidget {
  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reject this report?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Add a reason so the student understands the outcome.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonController,
            minLines: 2,
            maxLines: 4,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Keep report'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_reasonController.text),
          child: const Text('Reject report'),
        ),
      ],
    );
  }
}
