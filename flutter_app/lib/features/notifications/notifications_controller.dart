import 'package:flutter/foundation.dart';

import 'data/app_notification.dart';
import 'data/notifications_repository.dart';

enum NotificationsStatus { loading, ready, error }

/// Notification list + read-state management (read-only data; server-side
/// insert path untouched).
class NotificationsController extends ChangeNotifier {
  NotificationsController({required NotificationsRepository repository})
      : _repository = repository {
    load();
  }

  final NotificationsRepository _repository;

  NotificationsStatus _status = NotificationsStatus.loading;
  List<AppNotification> _notifications = const [];
  Object? _error;

  NotificationsStatus get status => _status;
  List<AppNotification> get notifications => _notifications;
  Object? get error => _error;
  int get unreadCount => _notifications.where((n) => !n.read).length;

  Future<void> load() async {
    _status = NotificationsStatus.loading;
    _error = null;
    notifyListeners();
    try {
      _notifications = await _repository.fetchRecent();
      _status = NotificationsStatus.ready;
    } catch (error) {
      _error = error;
      _status = NotificationsStatus.error;
    }
    notifyListeners();
  }

  Future<void> markRead(String id) async {
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index < 0) return;

    final existing = _notifications[index];
    if (existing.read) return;

    _notifications = List.of(_notifications);
    _notifications[index] = AppNotification(
      id: existing.id,
      title: existing.title,
      body: existing.body,
      type: existing.type,
      referenceId: existing.referenceId,
      read: true,
      createdAt: existing.createdAt,
    );
    notifyListeners();

    try {
      await _repository.markRead(id);
    } catch (error) {
      _notifications = List.of(_notifications);
      _notifications[index] = existing;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> markAllRead() async {
    final hasUnread = unreadCount > 0;
    if (!hasUnread) return;

    _notifications = _notifications.map(_asRead).toList();
    notifyListeners();

    try {
      await _repository.markAllRead();
    } catch (error) {
      await load();
      rethrow;
    }
  }

  static AppNotification _asRead(AppNotification n) => AppNotification(
        id: n.id,
        title: n.title,
        body: n.body,
        type: n.type,
        referenceId: n.referenceId,
        read: true,
        createdAt: n.createdAt,
      );
}
