import 'package:flutter/material.dart';

import '../models/provenance.dart';

/// Small badge showing where a parsed value came from.
class ProvenanceBadge extends StatelessWidget {
  const ProvenanceBadge(this.source, {super.key, this.compact = false});

  final ExtractionSource source;
  final bool compact;

  static const Map<ExtractionSource, String> _tooltips = {
    ExtractionSource.extracted: 'Read directly from the screenshot',
    ExtractionSource.derived: 'Calculated from visible values',
    ExtractionSource.missing: 'Not visible in the screenshot',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (source) {
      ExtractionSource.extracted => (
          scheme.primaryContainer,
          scheme.onPrimaryContainer,
        ),
      ExtractionSource.derived => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
      ExtractionSource.missing => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
        ),
    };

    return Tooltip(
      message: _tooltips[source],
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 7,
          vertical: compact ? 1 : 2,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          source.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: compact ? 8 : 10,
              ),
        ),
      ),
    );
  }
}