import 'package:flutter/material.dart';

import '../models/provenance.dart';
import 'provenance_badge.dart';

/// One labelled row of a parsed value with its provenance badge.
class ProvenanceValueRow<T> extends StatelessWidget {
  const ProvenanceValueRow({
    super.key,
    required this.label,
    required this.value,
    required this.format,
  });

  final String label;
  final ProvenanceValue<T> value;
  final String Function(T) format;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMissing = value.isMissing;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!isMissing)
            Text(
              format(value.value as T),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Text(
              'Not visible',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
                fontStyle: FontStyle.italic,
              ),
            ),
          const SizedBox(width: 8),
          ProvenanceBadge(value.source, compact: true),
        ],
      ),
    );
  }
}

/// Section header used inside preview cards.
class ImportSectionHeader extends StatelessWidget {
  const ImportSectionHeader(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}