import 'package:flutter/material.dart';

import '../../core/utils/relative_time.dart';
import 'data/app_notification.dart';
import 'notifications_controller.dart';

/// Notifications tab: own notifications (RLS-scoped), tap to mark read.
/// When [onOpen] is provided, tapping a notification with a `reference_id`
/// also opens the referenced report through the shell's detail flow.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.controller, this.onOpen});

  final NotificationsController controller;

  /// Invoked with the notification's `reference_id` after marking it read.
  final void Function(String referenceId)? onOpen;

  void _handleTap(AppNotification notification) {
    controller.markRead(notification.id);
    final referenceId = notification.referenceId;
    if (referenceId != null && referenceId.isNotEmpty) {
      onOpen?.call(referenceId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return switch (controller.status) {
          NotificationsStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          NotificationsStatus.error => _ErrorBody(onRetry: controller.load),
          NotificationsStatus.ready => Column(
              children: [
                if (controller.unreadCount > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: TextButton(
                        onPressed: controller.markAllRead,
                        child: const Text('Mark all as read'),
                      ),
                    ),
                  ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: controller.load,
                    child: controller.notifications.isEmpty
                        ? _EmptyBody()
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: controller.notifications.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final notification = controller.notifications[index];
                              return _NotificationTile(
                                notification: notification,
                                onTap: () => _handleTap(notification),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
        };
      },
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = !notification.read;

    return Card(
      margin: EdgeInsets.zero,
      color: unread ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35) : null,
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          _iconFor(notification.type),
          color: unread ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        title: Text(
          notification.title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (notification.body.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                notification.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              notification.createdAt == null
                  ? ''
                  : relativeTime(notification.createdAt!),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ),
        trailing: unread
            ? Icon(Icons.circle, size: 10, color: theme.colorScheme.primary)
            : null,
      ),
    );
  }

  static IconData _iconFor(String type) => switch (type) {
        'report_new' => Icons.fiber_new_outlined,
        'assignment' => Icons.person_add_alt_1_outlined,
        'report_deleted' => Icons.delete_outline,
        'report_restored' => Icons.restore_outlined,
        _ => Icons.update_outlined,
      };
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
        Icon(Icons.notifications_none, size: 48, color: theme.colorScheme.outline),
        const SizedBox(height: 12),
        Text(
          'No notifications yet.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Updates about your reports will appear here.',
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
            Text("Couldn't load notifications.", style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
