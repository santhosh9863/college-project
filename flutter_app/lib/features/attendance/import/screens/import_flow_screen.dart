import 'package:flutter/material.dart';

import '../import_controller.dart';
import '../models/parsed_linways_snapshot.dart';
import '../models/provenance.dart';
import '../widgets/provenance_badge.dart';
import '../widgets/validation_panel.dart';
import '../widgets/value_row.dart';

/// Full-screen import flow: select image → processing → extracted preview →
/// confirm. The confirmed [ParsedLinwaysSnapshot] is popped back to the
/// caller; nothing is written to storage.
class ImportFlowScreen extends StatelessWidget {
  const ImportFlowScreen({super.key, required this.controller});

  final LinwaysImportController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import Linways Screenshot')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return switch (controller.step) {
            ImportStep.idle => _IdleView(controller: controller),
            ImportStep.picking || ImportStep.processing =>
              const _ProcessingView(),
            ImportStep.preview => _PreviewView(controller: controller),
            ImportStep.error => _ErrorView(controller: controller),
          };
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Idle
// ---------------------------------------------------------------------------

class _IdleView extends StatelessWidget {
  const _IdleView({required this.controller});

  final LinwaysImportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Import a Linways Screenshot',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a screenshot of your overall attendance, subject-wise '
              'attendance, or profile from Linways. The text is read on your '
              'device — nothing is uploaded.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: controller.startImport,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Select Image'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Processing
// ---------------------------------------------------------------------------

class _ProcessingView extends StatelessWidget {
  const _ProcessingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Reading your screenshot…', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Text recognition happens on your device.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview
// ---------------------------------------------------------------------------

class _PreviewView extends StatelessWidget {
  const _PreviewView({required this.controller});

  final LinwaysImportController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    if (snapshot == null) return const _ProcessingView();

    final issues = controller.issues;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SourceHeader(snapshot: snapshot),
        if (snapshot.identity.hasAny) ...[
          const SizedBox(height: 16),
          _IdentityCard(identity: snapshot.identity),
        ],
        const SizedBox(height: 16),
        _OverallCard(overall: snapshot.overall),
        if (snapshot.subjects.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SubjectsCard(subjects: snapshot.subjects),
        ],
        if (snapshot.attendanceDate.isPresent ||
            snapshot.optional.hasAny) ...[
          const SizedBox(height: 16),
          _ContextCard(snapshot: snapshot),
        ],
        const SizedBox(height: 16),
        ValidationPanel(issues: issues),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: controller.hasErrors
              ? null
              : () => Navigator.of(context).pop(snapshot),
          icon: const Icon(Icons.check_circle_outline),
          label: Text(controller.hasErrors
              ? 'Fix the errors to use this import'
              : 'Confirm & use attendance'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: controller.startImport,
          icon: const Icon(Icons.image_outlined),
          label: const Text('Try another image'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SourceHeader extends StatelessWidget {
  const _SourceHeader({required this.snapshot});

  final ParsedLinwaysSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = switch (snapshot.source.screenType) {
      LinwaysScreenType.overallAttendance => 'Overall attendance screen',
      LinwaysScreenType.subjectWiseAttendance => 'Subject-wise attendance screen',
      LinwaysScreenType.studentProfile => 'Student profile screen',
      LinwaysScreenType.unknown => 'Unrecognized layout',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Extracted Preview',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            ProvenanceBadge(ExtractionSource.extracted),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          typeLabel,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        Text(
          'Imported at ${_formatTime(snapshot.source.capturedAt)} · everything below stays on this device',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  static String _formatTime(DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.identity});

  final ParsedIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ImportSectionHeader('Student information'),
            if (identity.studentName.isPresent)
              ProvenanceValueRow(
                label: 'Name',
                value: identity.studentName,
                format: (v) => v,
              ),
            if (identity.studentId.isPresent)
              ProvenanceValueRow(
                label: 'Register number',
                value: identity.studentId,
                format: (v) => v,
              ),
            if (identity.department.isPresent)
              ProvenanceValueRow(
                label: 'Department',
                value: identity.department,
                format: (v) => v,
              ),
            if (identity.semester.isPresent)
              ProvenanceValueRow(
                label: 'Semester',
                value: identity.semester,
                format: (v) => v,
              ),
            if (identity.section.isPresent)
              ProvenanceValueRow(
                label: 'Section',
                value: identity.section,
                format: (v) => v,
              ),
            if (identity.batch.isPresent)
              ProvenanceValueRow(
                label: 'Batch',
                value: identity.batch,
                format: (v) => v,
              ),
            if (identity.academicYear.isPresent)
              ProvenanceValueRow(
                label: 'Academic year',
                value: identity.academicYear,
                format: (v) => v,
              ),
            if (!identity.hasAny)
              Text(
                'No student information was visible in this screenshot.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
          ],
        ),
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.overall});

  final ParsedOverallAttendance overall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!overall.hasAny) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ImportSectionHeader('Overall attendance'),
              Text(
                'No overall attendance was found in this screenshot.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    final percentage = overall.percentage.value;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ImportSectionHeader(
              'Overall attendance',
              trailing: ProvenanceBadge(
                overall.percentage.source,
                compact: true,
              ),
            ),
            if (percentage != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    percentage.toStringAsFixed(1),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: _percentageColor(theme, percentage),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, left: 4),
                    child: Text('%', style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
            if (overall.conducted.isPresent)
              ProvenanceValueRow(
                label: 'Classes conducted',
                value: overall.conducted,
                format: (v) => '$v',
              ),
            if (overall.attended.isPresent)
              ProvenanceValueRow(
                label: 'Classes attended',
                value: overall.attended,
                format: (v) => '$v',
              ),
            if (overall.absent.isPresent)
              ProvenanceValueRow(
                label: 'Classes absent',
                value: overall.absent,
                format: (v) => '$v',
              ),
            if (overall.status.isPresent)
              ProvenanceValueRow(
                label: 'Status',
                value: overall.status,
                format: (v) => v,
              ),
          ],
        ),
      ),
    );
  }

  static Color _percentageColor(ThemeData theme, double percentage) {
    if (percentage < 75) return theme.colorScheme.error;
    if (percentage < 85) return Colors.orange.shade800;
    return Colors.green.shade700;
  }
}

class _SubjectsCard extends StatelessWidget {
  const _SubjectsCard({required this.subjects});

  final List<ParsedSubjectAttendance> subjects;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ImportSectionHeader(
              'Subject-wise attendance',
              trailing: Text(
                '${subjects.length} subject${subjects.length == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            for (final subject in subjects) ...[
              Text(
                subject.name.value ?? 'Subject',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              ProvenanceValueRow(
                label: 'Code',
                value: subject.code,
                format: (v) => v,
              ),
              ProvenanceValueRow(
                label: 'Faculty',
                value: subject.faculty,
                format: (v) => v,
              ),
              ProvenanceValueRow(
                label: 'Conducted',
                value: subject.conducted,
                format: (v) => '$v',
              ),
              ProvenanceValueRow(
                label: 'Attended',
                value: subject.attended,
                format: (v) => '$v',
              ),
              ProvenanceValueRow(
                label: 'Absent',
                value: subject.absent,
                format: (v) => '$v',
              ),
              ProvenanceValueRow(
                label: 'Percentage',
                value: subject.percentage,
                format: (v) => '${v.toStringAsFixed(1)}%',
              ),
              const Divider(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({required this.snapshot});

  final ParsedLinwaysSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ImportSectionHeader('Other visible details'),
            if (snapshot.attendanceDate.isPresent)
              ProvenanceValueRow(
                label: 'Attendance date',
                value: snapshot.attendanceDate,
                format: (v) => v,
              ),
            if (snapshot.optional.period.isPresent)
              ProvenanceValueRow(
                label: 'Period',
                value: snapshot.optional.period,
                format: (v) => v,
              ),
            if (snapshot.optional.classroom.isPresent)
              ProvenanceValueRow(
                label: 'Classroom',
                value: snapshot.optional.classroom,
                format: (v) => v,
              ),
            if (snapshot.optional.timetable.isPresent)
              ProvenanceValueRow(
                label: 'Timetable',
                value: snapshot.optional.timetable,
                format: (v) => v,
              ),
            if (snapshot.optional.examInfo.isPresent)
              ProvenanceValueRow(
                label: 'Exam info',
                value: snapshot.optional.examInfo,
                format: (v) => v,
              ),
            if (snapshot.optional.marks.isPresent)
              ProvenanceValueRow(
                label: 'Marks',
                value: snapshot.optional.marks,
                format: (v) => v,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.controller});

  final LinwaysImportController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Could not import this screenshot',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              controller.errorMessage ?? 'Something went wrong.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: controller.startImport,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Try another image'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}

// Extension helper: whether any identity field is present.
extension on ParsedIdentity {
  bool get hasAny =>
      studentName.isPresent ||
      studentId.isPresent ||
      department.isPresent ||
      semester.isPresent ||
      section.isPresent ||
      batch.isPresent ||
      academicYear.isPresent;
}

extension on ParsedOptionalInfo {
  bool get hasAny =>
      timetable.isPresent ||
      period.isPresent ||
      classroom.isPresent ||
      examInfo.isPresent ||
      marks.isPresent;
}