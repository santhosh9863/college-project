import 'package:flutter/material.dart';

import '../../services/auth_controller.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/data/linways_attendance_repository.dart';
import '../attendance/widgets/attendance_card.dart';
import '../notifications/data/notifications_repository.dart';
import '../notifications/notifications_controller.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/data/reports_repository.dart';
import '../reports/reports_controller.dart';
import '../reports/reports_screen.dart';

/// Authenticated dashboard shell: Home (name, community, attendance),
/// Reports, Notifications and Profile destinations.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AuthController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  late final AttendanceController _attendanceController;
  late final ReportsController _reportsController;
  late final NotificationsController _notificationsController;

  @override
  void initState() {
    super.initState();
    _attendanceController = AttendanceController(
      repository: LinwaysAttendanceRepository(),
    );
    _reportsController = ReportsController(
      repository: ReportsRepository(),
    );
    _notificationsController = NotificationsController(
      repository: NotificationsRepository(),
    );
  }

  @override
  void dispose() {
    _attendanceController.dispose();
    _reportsController.dispose();
    _notificationsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          switch (_selectedIndex) {
            0 => 'college project',
            1 => 'Community reports',
            2 => 'Notifications',
            _ => 'Profile',
          },
        ),
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _HomeTab(
            controller: widget.controller,
            attendanceController: _attendanceController,
            onAttendanceRefresh: _attendanceController.refresh,
            onAttendanceReSignIn: widget.controller.logout,
          ),
          ReportsScreen(controller: _reportsController),
          NotificationsScreen(controller: _notificationsController),
          ProfileScreen(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.controller,
    required this.attendanceController,
    required this.onAttendanceRefresh,
    required this.onAttendanceReSignIn,
  });

  final AuthController controller;
  final AttendanceController attendanceController;
  final Future<void> Function() onAttendanceRefresh;
  final VoidCallback onAttendanceReSignIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = controller.profile;
    final community = controller.community;
    final firstName = (profile?.fullName ?? 'Student').split(' ').first;

    return RefreshIndicator(
      onRefresh: onAttendanceRefresh,
      child: AnimatedBuilder(
        animation: attendanceController,
        builder: (context, _) {
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Hi, $firstName',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                community == null
                    ? 'Your community is being assigned by the college.'
                    : 'Your class community from verified college records.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.group_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  title: Text(community?.displayName ?? 'Community pending'),
                  subtitle: Text(
                    community == null
                        ? 'Assignments and reports will be available once assigned.'
                        : 'Course · Year · Semester · Section',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AttendanceCard(
                controller: attendanceController,
                onRefresh: onAttendanceRefresh,
                onReSignIn: onAttendanceReSignIn,
              ),
            ],
          );
        },
      ),
    );
  }
}
