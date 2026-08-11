import 'package:flutter/material.dart';

import '../../services/auth_controller.dart';

/// Profile tab: verified student details, community membership and sign-out.
/// Signing out removes both the Supabase session and the device-held Linways
/// session (secure session restoration and logout).
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.controller});

  final AuthController controller;

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your Linways session and sign-in will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = controller.profile;
    final sessionUser = controller.currentUser;
    final community = controller.community;

    final displayName = profile?.fullName ?? sessionUser?.email ?? 'Student';
    final email = profile?.email ?? sessionUser?.email ?? '—';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        CircleAvatar(
          radius: 36,
          child: Text(
            displayName.isEmpty ? '?' : displayName[0],
            style: theme.textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          displayName,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(
          email,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        Card(
          child: Column(
            children: [
              _ProfileRow(label: 'Role', value: profile?.role ?? 'student'),
              _ProfileRow(label: 'Student ID', value: profile?.studentId ?? '—'),
              _ProfileRow(label: 'Semester', value: '${profile?.semester ?? '—'}'),
              _ProfileRow(label: 'Section', value: profile?.section ?? '—'),
              _ProfileRow(
                label: 'Community',
                value: community?.displayName ?? 'Pending',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => _confirmLogout(context),
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
            side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
          ),
        ),
      ],
    );
  }
}

class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(
        label,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: Text(
        value,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
