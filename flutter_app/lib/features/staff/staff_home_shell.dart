import 'package:flutter/material.dart';

import '../../services/auth_controller.dart';
import '../notifications/data/notifications_repository.dart';
import '../notifications/notifications_controller.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/data/reports_repository.dart';
import 'data/staff_reports_repository.dart';
import 'staff_queue_controller.dart';
import 'staff_queue_screen.dart';

/// Staff dashboard shell. Panel selection follows `profiles.role`; the HOD
/// and technician panels (Phases 2.4/2.5) render the D1-scoped routed queue
/// through [StaffQueueScreen]; operations/admin show a placeholder until
/// their phase ships.
class StaffHomeShell extends StatefulWidget {
  const StaffHomeShell({super.key, required this.controller, required this.role});

  final AuthController controller;
  final String role;

  @override
  State<StaffHomeShell> createState() => _StaffHomeShellState();
}

class _StaffHomeShellState extends State<StaffHomeShell> {
  int _selectedIndex = 0;

  late final StaffQueueController _queueController;
  late final NotificationsController _notificationsController;

  @override
  void initState() {
    super.initState();
    _queueController = StaffQueueController(
      repository: StaffReportsRepository(),
      detailRepository: ReportsRepository(
        currentUserId: widget.controller.currentUser?.id ?? '',
      ),
    );
    _notificationsController = NotificationsController(
      repository: NotificationsRepository(),
    );
  }

  @override
  void dispose() {
    _queueController.dispose();
    _notificationsController.dispose();
    super.dispose();
  }

  String get _panelTitle => switch (widget.role) {
        'hod' => 'Department reports',
        'technician' => 'Technician panel',
        'operations' => 'Operations panel',
        'admin' => 'Admin panel',
        _ => 'Staff',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_selectedIndex) {
            0 => _panelTitle,
            1 => 'Notifications',
            _ => 'Profile',
          },
        ),
      ),
body: IndexedStack(
        index: _selectedIndex,
        children: [
          if (widget.role == 'hod' || widget.role == 'technician')
            StaffQueueScreen(controller: _queueController)
          else
            _PanelComingSoon(role: widget.role),
          NotificationsScreen(controller: _notificationsController),
          ProfileScreen(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _notificationsController,
        builder: (context, _) {
          final unread = _notificationsController.unreadCount;
          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: const Icon(Icons.receipt_long),
                label: 'Queue',
              ),
              NavigationDestination(
                icon: Badge.count(
                  count: unread,
                  isLabelVisible: unread > 0,
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge.count(
                  count: unread,
                  isLabelVisible: unread > 0,
                  child: const Icon(Icons.notifications),
                ),
                label: 'Notifications',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PanelComingSoon extends StatelessWidget {
  const _PanelComingSoon({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = switch (role) {
      'technician' => 'Technician',
      'operations' => 'Operations',
      'admin' => 'Admin',
      _ => 'Staff',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.construction_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              '$label panel',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'This panel is being built in a later phase.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
