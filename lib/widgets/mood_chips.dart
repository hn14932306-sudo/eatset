import 'package:flutter/material.dart';

import '../models/mood.dart';

class MoodChips extends StatelessWidget {
  const MoodChips({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final Mood value;
  final ValueChanged<Mood> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: Mood.values.map((m) {
        final selected = m == value;
        return FilterChip(
          label: Text(m.labelZh),
          selected: selected,
          onSelected: (_) => onChanged(m),
          showCheckmark: false,
        );
      }).toList(),
    );
  }
}
