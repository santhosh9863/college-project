import 'package:college_project_app/features/notifications/data/app_notification.dart';
import 'package:college_project_app/features/notifications/data/notifications_repository.dart';
import 'package:college_project_app/features/notifications/notifications_controller.dart';
import 'package:college_project_app/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

AppNotification _notification({
  String id = 'n-1',
  String type = 'status_change',
  String title = 'Status updated',
  String? referenceId = 'r-1',
  bool read = false,
}) =>
    AppNotification(
      id: id,
      title: title,
      body: 'Your report is now in progress.',
      type: type,
      referenceId: referenceId,
      read: read,
      createdAt: DateTime(2026, 8, 15),
    );

class _FakeNotificationsRepository extends NotificationsRepository {
  _FakeNotificationsRepository({List<AppNotification>? initial})
      : rows = List.of(
          initial ??
              [
                _notification(),
                _notification(id: 'n-2', title: 'New report', type: 'report_new', read: true),
              ],
        ),
        super(client: SupabaseClient(
          'http://localhost',
          'anon-key',
          authOptions: AuthClientOptions(autoRefreshToken: false),
        ));

  List<AppNotification> rows;
  final List<String> readLog = [];

  @override
  Future<List<AppNotification>> fetchRecent() async => List.of(rows);

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
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
  }

  group('NotificationsScreen', () {
    testWidgets('renders the inbox with unread styling and mark-all button',
        (tester) async {
      final controller = NotificationsController(
        repository: _FakeNotificationsRepository(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: NotificationsScreen(controller: controller))),
      );
      await settle(tester);

      expect(find.text('Status updated'), findsOneWidget);
      expect(find.text('New report'), findsOneWidget);
      expect(find.text('Mark all as read'), findsOneWidget);
    });

    testWidgets('tapping a notification marks it read and opens the reference',
        (tester) async {
      final repo = _FakeNotificationsRepository();
      final controller = NotificationsController(repository: repo);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationsScreen(
              controller: controller,
              onOpen: opened.add,
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Status updated'));
      await settle(tester);

      expect(repo.readLog, ['n-1']);
      expect(opened, ['r-1']);
    });

    testWidgets('tapping does not open when the reference is absent',
        (tester) async {
      final repo = _FakeNotificationsRepository(
        initial: [_notification(referenceId: null)],
      );
      final controller = NotificationsController(repository: repo);
      final opened = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationsScreen(
              controller: controller,
              onOpen: opened.add,
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Status updated'));
      await settle(tester);

      expect(repo.readLog, ['n-1']);
      expect(opened, isEmpty);
    });

    testWidgets('mark all as read clears the unread emphasis', (tester) async {
      final controller = NotificationsController(
        repository: _FakeNotificationsRepository(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: NotificationsScreen(controller: controller))),
      );
      await settle(tester);

      await tester.tap(find.text('Mark all as read'));
      await settle(tester);

      expect(find.text('Mark all as read'), findsNothing);
    });

    testWidgets('shows the empty state', (tester) async {
      final controller = NotificationsController(
        repository: _FakeNotificationsRepository(initial: const []),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: NotificationsScreen(controller: controller))),
      );
      await settle(tester);

      expect(find.text('No notifications yet.'), findsOneWidget);
    });
  });
}