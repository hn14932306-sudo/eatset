import 'package:flutter/material.dart';

import '../models/mood.dart';

class MoodChips extends StatelessWidget {
  const MoodChips({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final Mood value;
  final ValueChanged<Mood> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: compact ? 6 : 8,
      children: Mood.values.map((m) {
        final selected = m == value;
        final scheme = Theme.of(context).colorScheme;
        return FilterChip(
          label: Text(
            m.labelZh,
            style: compact ? Theme.of(context).textTheme.labelMedium : null,
          ),
          selected: selected,
          onSelected: (_) => onChanged(m),
          showCheckmark: false,
          selectedColor: scheme.secondaryContainer,
          visualDensity:
              compact ? VisualDensity.compact : VisualDensity.standard,
          materialTapTargetSize: compact
              ? MaterialTapTargetSize.shrinkWrap
              : MaterialTapTargetSize.padded,
        );
      }).toList(),
    );
  }
}
