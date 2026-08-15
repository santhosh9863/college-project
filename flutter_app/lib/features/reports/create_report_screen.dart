import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'create_report_controller.dart';
import 'data/evidence_mime.dart';
import 'data/models/report_priority.dart';

/// Create-report flow: title, description, category (from the database),
/// priority and optional photo evidence. Identity snapshots (reporter,
/// community, department) come from the authenticated state — never input.
class CreateReportScreen extends StatefulWidget {
  const CreateReportScreen({super.key, required this.controller});

  final CreateReportController controller;

  @override
  State<CreateReportScreen> createState() => _CreateReportScreenState();
}

class _CreateReportScreenState extends State<CreateReportScreen> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  bool _attempted = false;

  CreateReportController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickEvidence() async {
    final files = await _picker.pickMultiImage(
      requestFullMetadata: false,
      limit: 5 - _controller.evidence.length,
    );
    if (files.isEmpty || !mounted) return;
    for (final file in files) {
      final draft = _toDraft(file);
      if (draft == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Only images and PDFs are supported.')),
        );
        continue;
      }
      _controller.addEvidence(draft);
    }
  }

  EvidenceDraft? _toDraft(XFile file) {
    final name = file.name;
    final contentType = evidenceMimeTypeFromName(name);
    if (contentType == 'application/octet-stream') return null;
    return EvidenceDraft(path: file.path, fileName: name, contentType: contentType);
  }

  Future<void> _submit() async {
    if (!_controller.canSubmit) {
      setState(() => _attempted = true);
      return;
    }
    final reportId = await _controller.submit();
    if (reportId != null && mounted) {
      Navigator.of(context).pop(reportId);
    }
  }

  String? get _validationMessage =>
      _attempted ? _controller.validationMessage : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New report')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_controller.error != null) ...[
            Card(
              color: theme.colorScheme.errorContainer,
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _controller.error!,
                        style: TextStyle(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _titleController,
            maxLength: 200,
            onChanged: _controller.setTitle,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Title',
              hintText: 'Short summary of the problem',
              errorText: _validationMessage != null &&
                      _titleController.text.trim().isEmpty
                  ? 'Add a short title.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 4,
            maxLength: 2000,
            onChanged: _controller.setDescription,
            decoration: InputDecoration(
              labelText: 'Description',
              hintText: 'What happened, where, and what is needed',
              alignLabelWithHint: true,
              errorText: _validationMessage != null &&
                      _descriptionController.text.trim().isEmpty
                  ? 'Describe the problem.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _controller.categoryId,
            decoration: InputDecoration(
              labelText: 'Category',
              prefixIcon: const Icon(Icons.category_outlined),
              errorText: _validationMessage != null && _controller.categoryId == null
                  ? 'Choose a category.'
                  : null,
            ),
            items: _controller.categoriesFailed
                ? const []
                : [
                    for (final category in _controller.categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      ),
                  ],
            onChanged: _controller.setCategoryId,
          ),
          if (_controller.categoriesFailed) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  "Categories couldn't load.",
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
                TextButton(
                  onPressed: _controller.retryCategories,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Priority',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            emptySelectionAllowed: true,
            segments: [
              for (final priority in ReportPriority.values)
                if (priority != ReportPriority.unknown)
                  ButtonSegment(
                    value: priority.apiValue,
                    label: Text(priority.label),
                    icon: Icon(_priorityIcon(priority), size: 16),
                  ),
            ],
            selected: {
              if (_controller.priority != null) _controller.priority!,
            },
            onSelectionChanged: (selection) =>
                _controller.setPriority(selection.first),
          ),
          if (_validationMessage != null && _controller.priority == null) ...[
            const SizedBox(height: 8),
            Text(
              'Choose a priority.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Evidence',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (_controller.evidence.isNotEmpty)
                Text(
                  '${_controller.evidence.length}/5',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Photos of the issue (optional, up to 5).',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          if (_controller.evidence.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _controller.evidence.length; i++)
                  _EvidenceThumb(
                    draft: _controller.evidence[i],
                    onRemove: () => _controller.removeEvidenceAt(i),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _controller.evidence.length >= 5 ? null : _pickEvidence,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add photos'),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _controller.submitting ? null : _submit,
            icon: _controller.submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_controller.submitting ? 'Submitting…' : 'Submit report'),
          ),
          const SizedBox(height: 8),
          Text(
            'Your report starts as Pending and becomes visible to your '
            'community once reviewed.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  IconData _priorityIcon(ReportPriority priority) => switch (priority) {
        ReportPriority.high || ReportPriority.critical => Icons.arrow_upward,
        ReportPriority.low => Icons.arrow_downward,
        _ => Icons.remove,
      };
}

class _EvidenceThumb extends StatelessWidget {
  const _EvidenceThumb({required this.draft, required this.onRemove});

  final EvidenceDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: draft.contentType == 'application/pdf'
              ? Container(
                  width: 88,
                  height: 88,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: const Icon(Icons.picture_as_pdf, size: 36),
                )
              : Image.file(
                  File(draft.path),
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 88,
                    height: 88,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
        ),
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, size: 16, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
