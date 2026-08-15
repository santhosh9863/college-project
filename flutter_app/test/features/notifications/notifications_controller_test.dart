import 'package:college_project_app/features/notifications/data/app_notification.dart';
import 'package:college_project_app/features/notifications/data/notifications_repository.dart';
import 'package:college_project_app/features/notifications/notifications_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AppNotification _notification({
  String id = 'n-1',
  String type = 'status_change',
  String? referenceId = 'r-1',
  bool read = false,
}) =>
    AppNotification(
      id: id,
      title: 'Status updated',
      body: 'Your report is now in progress.',
      type: type,
      referenceId: referenceId,
      read: read,
      createdAt: DateTime(2026, 8, 15),
    );

class _FakeNotificationsRepository extends NotificationsRepository {
  _FakeNotificationsRepository({List<AppNotification>? initial})
      : rows = List.of(initial ?? [_notification(), _notification(id: 'n-2', read: true)]),
        super(client: SupabaseClient('http://localhost', 'anon-key'));

  List<AppNotification> rows;
  int fetchCalls = 0;
  final List<String> readLog = [];
  int markAllCalls = 0;
  bool failNext = false;

  @override
  Future<List<AppNotification>> fetchRecent() async {
    fetchCalls++;
    if (failNext) {
      failNext = false;
      throw Exception('fetch failed');
    }
    return List.of(rows);
  }

  @override
  Future<void> markRead(String id) async {
    readLog.add(id);
    final index = rows.indexWhere((n) => n.id == id);
    if (index >= 0) {
      final n = rows[index];
      rows[index] = AppNotification(
        id: n.id,
        title: n.title,
        body: n.body,
        type: n.type,
        referenceId: n.referenceId,
        read: true,
        createdAt: n.createdAt,
      );
    }
  }

  @override
  Future<void> markAllRead() async {
    markAllCalls++;
    rows = rows
        .map((n) => AppNotification(
              id: n.id,
              title: n.title,
              body: n.body,
              type: n.type,
              referenceId: n.referenceId,
              read: true,
              createdAt: n.createdAt,
            ))
        .toList();
  }
}

void main() {
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('NotificationsController', () {
    test('loads the inbox and counts unread', () async {
      final repo = _FakeNotificationsRepository();
      final controller = NotificationsController(repository: repo);
      await settle();

      expect(controller.status, NotificationsStatus.ready);
      expect(controller.notifications, hasLength(2));
      expect(controller.unreadCount, 1);
    });

    test('markRead optimistically updates and persists', () async {
      final repo = _FakeNotificationsRepository();
      final controller = NotificationsController(repository: repo);
      await settle();

      await controller.markRead('n-1');

      expect(repo.readLog, ['n-1']);
      expect(controller.unreadCount, 0);
      expect(controller.notifications.first.read, isTrue);
    });

    test('markRead ignores already-read rows', () async {
      final repo = _FakeNotificationsRepository();
      final controller = NotificationsController(repository: repo);
      await settle();

      await controller.markRead('n-2');

      expect(repo.readLog, isEmpty);
    });

    test('markAllRead flips every row and reloads on failure', () async {
      final repo = _FakeNotificationsRepository();
      final controller = NotificationsController(repository: repo);
      await settle();

      await controller.markAllRead();

      expect(repo.markAllCalls, 1);
      expect(controller.unreadCount, 0);
    });

    test('load exposes errors with the error state', () async {
      final repo = _FakeNotificationsRepository()..failNext = true;
      final controller = NotificationsController(repository: repo);
      await settle();

      expect(controller.status, NotificationsStatus.error);
      expect(controller.error, isNotNull);
    });
  });
}