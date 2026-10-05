import 'package:flutter/material.dart';

import 'data/models/report_comment.dart';
import 'data/models/report_status.dart';
import 'report_detail_controller.dart';
import 'widgets/report_detail_widgets.dart';

/// Report detail: status, priority, description, activity timeline, evidence,
/// support, comments and (for the author of a pending report) cancellation.
/// All writes are optimistic in the controller and enforced by RLS.
class ReportDetailScreen extends StatefulWidget {
  const ReportDetailScreen({
    super.key,
    required this.controller,
    this.onOpenReport,
  });

  final ReportDetailController controller;

  /// Opens a different report by id. Supplied by the parent, which owns the
  /// repository — this screen is deliberately given no data access of its own.
  ///
  /// When omitted, the duplicate notice renders without its "view the earlier
  /// report" link rather than dead-ending on a tap. Both remaining call sites
  /// (feed and home shell) can supply it.
  final Future<void> Function(String reportId)? onOpenReport;

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

  Future<void> _openReport(String reportId) async {
    final open = widget.onOpenReport;
    if (open == null) return;
    await open(reportId);
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
          ReportDetailErrorBody(error: controller.error, onRetry: controller.load),
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
          ReportHeaderCard(report: report, assigneeId: detail.activeAssigneeId),
          if (report.isDuplicate) ...[
            const SizedBox(height: 12),
            DuplicateNoticeCard(
              report: report,
              onOpenCanonical: widget.onOpenReport == null
                  ? null
                  : () => _openReport(report.duplicateOf!),
            ),
          ],
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
          if (detail.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            ReportSectionCard(
              title: 'Evidence',
              child: GridView.count(
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
          ],
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
