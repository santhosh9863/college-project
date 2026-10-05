import 'package:flutter/material.dart';

import '../../services/auth_controller.dart';
import '../analytics/analytics_controller.dart';
import '../analytics/data/analytics_repository.dart';
import '../analytics/insights_screen.dart';
import '../attendance/attendance_controller.dart';
import '../attendance/data/linways_attendance_repository.dart';
import '../attendance/import/import_controller.dart';
import '../attendance/import/models/parsed_linways_snapshot.dart';
import '../attendance/import/ocr/mlkit_ocr_service.dart';
import '../attendance/import/image/image_pick_service.dart';
import '../attendance/import/screens/import_flow_screen.dart';
import '../attendance/widgets/attendance_card.dart';
import '../notifications/data/notifications_repository.dart';
import '../notifications/notifications_controller.dart';
import '../notifications/notifications_screen.dart';
import '../profile/profile_screen.dart';
import '../reports/data/categories_repository.dart';
import '../reports/data/reports_repository.dart';
import '../reports/report_detail_screen.dart';
import '../reports/reports_controller.dart';
import '../reports/reports_screen.dart';
import '../staff/staff_home_shell.dart';

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
  late final LinwaysImportController _importController;

  @override
  void initState() {
    super.initState();
    _attendanceController = AttendanceController(
      repository: LinwaysAttendanceRepository(),
    );
    _reportsController = ReportsController(
      repository: ReportsRepository(
        currentUserId: widget.controller.currentUser?.id ?? '',
      ),
      categoriesRepository: CategoriesRepository(),
    );
    _notificationsController = NotificationsController(
      repository: NotificationsRepository(),
    );
    _importController = LinwaysImportController(
      ocr: MlKitOcrService(),
      picker: GalleryImagePickService(),
      profile: widget.controller.profile,
      community: widget.controller.community,
    );
  }

  @override
  void dispose() {
    _attendanceController.dispose();
    _reportsController.dispose();
    _notificationsController.dispose();
    _importController.dispose();
    super.dispose();
  }

  Future<void> _openImportFlow() async {
    final snapshot = await Navigator.of(context).push<ParsedLinwaysSnapshot>(
      MaterialPageRoute(
        builder: (_) => ImportFlowScreen(controller: _importController),
      ),
    );
    if (snapshot != null) {
      _attendanceController.useImported(snapshot);
    }
  }

  Future<void> _openNotificationReport(String reportId) async {
    await _pushDetail(reportId);
    _reportsController.load();
  }

  /// Pushes report detail, letting the pushed screen navigate onwards (used by
  /// the duplicate notice to reach the canonical report).
  Future<void> _pushDetail(String reportId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReportDetailScreen(
          controller: _reportsController.detailControllerFor(reportId),
          onOpenReport: _pushDetail,
        ),
      ),
    );
  }

  Future<void> _openInsights() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InsightsScreen(
          controller: AnalyticsController(repository: AnalyticsRepository()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.controller.profile?.role;
    if (role != null && role != 'student') {
      return StaffHomeShell(controller: widget.controller, role: role);
    }
    return _buildStudentShell(context);
  }

  Widget _buildStudentShell(BuildContext context) {
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
        actions: [
          IconButton(
            tooltip: 'Insights',
            icon: const Icon(Icons.insights_outlined),
            onPressed: _openInsights,
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          _HomeTab(
            controller: widget.controller,
            attendanceController: _attendanceController,
            onAttendanceRefresh: _attendanceController.refresh,
            onAttendanceReSignIn: widget.controller.logout,
            onImportScreenshot: _openImportFlow,
          ),
          ReportsScreen(
            controller: _reportsController,
            profile: widget.controller.profile,
            community: widget.controller.community,
          ),
          NotificationsScreen(
            controller: _notificationsController,
            onOpen: _openNotificationReport,
          ),
          ProfileScreen(controller: widget.controller),
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _notificationsController,
        builder: (context, _) {
          final unread = _notificationsController.unreadCount;
          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
              if (index == 2) _notificationsController.load();
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              const NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long),
                label: 'Reports',
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

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.controller,
    required this.attendanceController,
    required this.onAttendanceRefresh,
    required this.onAttendanceReSignIn,
    required this.onImportScreenshot,
  });

  final AuthController controller;
  final AttendanceController attendanceController;
  final Future<void> Function() onAttendanceRefresh;
  final VoidCallback onAttendanceReSignIn;
  final VoidCallback onImportScreenshot;

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
                onImportScreenshot: onImportScreenshot,
              ),
            ],
          );
        },
      ),
    );
  }
}
