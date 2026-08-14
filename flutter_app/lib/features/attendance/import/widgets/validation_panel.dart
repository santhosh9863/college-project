import 'package:flutter/material.dart';

import '../models/validation_issue.dart';

/// Renders the validation findings grouped by severity.
class ValidationPanel extends StatelessWidget {
  const ValidationPanel({super.key, required this.issues});

  final List<ValidationIssue> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return const SizedBox.shrink();

    final errors = issues.where((i) => i.severity == ValidationSeverity.error).toList();
    final warnings = issues.where((i) => i.severity == ValidationSeverity.warning).toList();
    final infos = issues.where((i) => i.severity == ValidationSeverity.info).toList();

    final children = <Widget>[];
    if (errors.isNotEmpty) {
      children.add(_Group('Errors', Icons.error_outline, errors, context));
    }
    if (warnings.isNotEmpty) {
      children.add(_Group('Warnings', Icons.warning_amber_rounded, warnings, context));
    }
    if (infos.isNotEmpty) {
      children.add(_Group('Notes', Icons.info_outline, infos, context));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Validation', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.icon, this.issues, this.context);

  final String title;
  final IconData icon;
  final List<ValidationIssue> issues;
  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = issues.first.severity == ValidationSeverity.error
        ? theme.colorScheme.error
        : issues.first.severity == ValidationSeverity.warning
            ? Colors.amber.shade800
            : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                '$title (${issues.length})',
                style: theme.textTheme.labelLarge?.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(left: 22, bottom: 2),
              child: Text(
                issue.message,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}