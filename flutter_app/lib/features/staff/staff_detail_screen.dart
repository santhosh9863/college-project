import 'package:flutter/material.dart';

import '../reports/data/models/report_status.dart';
import '../reports/widgets/report_detail_widgets.dart';
import 'data/assignable_staff.dart';
import 'staff_detail_controller.dart';

/// Staff report detail (HOD/technician): full report view plus the lifecycle
/// actions the staff role may take (review/accept, mark in progress, resolve,
/// reject with a reason). Actions are offered per the approved lifecycle
/// matrix; the database remains the enforcement.
class StaffDetailScreen extends StatefulWidget {
  const StaffDetailScreen({super.key, required this.controller});

  final StaffDetailController controller;

  @override
  State<StaffDetailScreen> createState() => _StaffDetailScreenState();
}

class _StaffDetailScreenState extends State<StaffDetailScreen> {
  final _commentController = TextEditingController();

  StaffDetailController get _controller => widget.controller;

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

  Future<void> _assign() async {
    final staff = await showDialog<AssignableStaff>(
      context: context,
      builder: (context) => _AssignDialog(controller: _controller),
    );
    if (staff == null) return;
    final accepted = await _controller.assignTo(staff.id);
    if (accepted) {
      _showMessage('Assigned to ${staff.fullName}.');
    } else {
      _showMessage("Couldn't assign the report. Please try again.");
    }
  }

  Future<void> _unassign() async {
    final accepted = await _controller.unassign();
    if (accepted) {
      _showMessage('Assignment removed.');
    } else {
      _showMessage("Couldn't remove the assignment. Please try again.");
    }
  }

  Future<void> _moderateDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this report?'),
        content: const Text(
          'The report will be hidden from students. Its status is kept and '
          'it can be restored later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep report'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete report'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final accepted = await _controller.moderate(restore: false);
    if (accepted) {
      _showMessage('Report deleted.');
    } else {
      _showMessage("Couldn't delete the report. Please try again.");
    }
  }

  Future<void> _moderateRestore() async {
    final accepted = await _controller.moderate(restore: true);
    if (accepted) {
      _showMessage('Report restored.');
    } else {
      _showMessage("Couldn't restore the report. Please try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Department report')),
      body: switch (controller.status) {
        StaffDetailStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        StaffDetailStatus.error =>
          ReportDetailErrorBody(error: controller.error, onRetry: controller.load),
        StaffDetailStatus.ready => _buildDetail(context),
      },
      bottomNavigationBar: controller.status == StaffDetailStatus.ready &&
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
          if (controller.canManageAssignments) ...[
            const SizedBox(height: 12),
            _AssignmentCard(
              controller: controller,
              onAssign: _assign,
              onUnassign: _unassign,
            ),
          ],
          if (controller.canModerate) ...[
            const SizedBox(height: 12),
            _ModerationCard(
              controller: controller,
              onDelete: _moderateDelete,
              onRestore: _moderateRestore,
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

  final StaffDetailController controller;
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
                  label: Text(_actionLabel(others[i], controller.report?.status)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _actionLabel(ReportStatus status, [ReportStatus? current]) {
  if (current == ReportStatus.resolved || current == ReportStatus.rejected) {
    return switch (status) {
      ReportStatus.underReview => 'Reopen review',
      ReportStatus.inProgress => 'Reopen work',
      _ => status.label,
    };
  }
  return switch (status) {
    ReportStatus.underReview => 'Start review',
    ReportStatus.inProgress => 'Mark in progress',
    ReportStatus.resolved => 'Mark resolved',
    ReportStatus.closed => 'Close report',
    _ => status.label,
  };
}

IconData _actionIcon(ReportStatus status) => switch (status) {
      ReportStatus.underReview => Icons.rate_review_outlined,
      ReportStatus.inProgress => Icons.play_circle_outline,
      ReportStatus.resolved => Icons.check_circle_outline,
      ReportStatus.closed => Icons.lock_outline,
      _ => Icons.arrow_forward,
    };

/// Assignment management card (operations/admin only): shows the current
/// assignee and offers assign/change/unassign. Push-only (D3) — assignment
/// takes effect immediately.
class _AssignmentCard extends StatelessWidget {
  const _AssignmentCard({
    required this.controller,
    required this.onAssign,
    required this.onUnassign,
  });

  final StaffDetailController controller;
  final Future<void> Function() onAssign;
  final Future<void> Function() onUnassign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final assigneeName = controller.assigneeName;
    return ReportSectionCard(
      title: 'Assignment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                assigneeName != null
                    ? Icons.person_pin_circle_outlined
                    : Icons.person_off_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  assigneeName ?? 'Not assigned',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: assigneeName != null
                        ? null
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: controller.assignmentInFlight ? null : onAssign,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: Text(assigneeName != null ? 'Change' : 'Assign'),
              ),
              if (assigneeName != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  onPressed:
                      controller.assignmentInFlight ? null : onUnassign,
                  tooltip: 'Remove assignment',
                  icon: const Icon(Icons.link_off),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Staff picker dialog backed by the ops/admin `list_assignable_staff` RPC.
class _AssignDialog extends StatelessWidget {
  const _AssignDialog({required this.controller});

  final StaffDetailController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staff = controller.staffDirectory;
    return AlertDialog(
      title: const Text('Assign to staff'),
      content: SizedBox(
        width: double.maxFinite,
        child: staff.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'No staff members available.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final member in staff)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.badge_outlined),
                      title: Text(member.fullName),
                      subtitle: Text(
                        [
                          _roleLabel(member.role),
                          if (member.departmentCode != null)
                            member.departmentCode!,
                        ].join(' · '),
                      ),
                      onTap: () => Navigator.of(context).pop(member),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  static String _roleLabel(String role) => switch (role) {
        'hod' => 'HOD',
        'technician' => 'Technician',
        'operations' => 'Operations',
        'admin' => 'Admin',
        _ => role,
      };
}

/// Moderation card (admin only): soft-deletes a report or restores a
/// soft-deleted one. Status is preserved in both directions (u8/F1); the
/// database enforces the admin-only restore.
class _ModerationCard extends StatelessWidget {
  const _ModerationCard({
    required this.controller,
    required this.onDelete,
    required this.onRestore,
  });

  final StaffDetailController controller;
  final Future<void> Function() onDelete;
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final deleted = controller.isDeleted;
    return ReportSectionCard(
      title: 'Moderation',
      child: Row(
        children: [
          Icon(
            deleted ? Icons.restore_from_trash_outlined : Icons.delete_outline,
            size: 20,
            color: deleted
                ? theme.colorScheme.primary
                : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              deleted
                  ? 'This report is hidden from students.'
                  : 'Soft-delete hides the report from students. Its status is kept.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          if (deleted)
            FilledButton.tonalIcon(
              onPressed: controller.assignmentInFlight ? null : onRestore,
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('Restore'),
            )
          else
            OutlinedButton.icon(
              onPressed: controller.assignmentInFlight ? null : onDelete,
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete'),
            ),
        ],
      ),
    );
  }
}

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
