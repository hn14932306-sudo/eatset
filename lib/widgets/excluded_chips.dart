import 'package:flutter/material.dart';

/// 排除芯片列表：超過 [collapseAfter] 預設收合，顯示「還有 N 項」。
class ExcludedChipsWrap extends StatefulWidget {
  const ExcludedChipsWrap({
    super.key,
    required this.chips,
    this.collapseAfter = 10,
  });

  final List<Widget> chips;
  final int collapseAfter;

  @override
  State<ExcludedChipsWrap> createState() => _ExcludedChipsWrapState();
}

class _ExcludedChipsWrapState extends State<ExcludedChipsWrap> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final chips = widget.chips;
    final limit = widget.collapseAfter;
    final needsCollapse = chips.length > limit;
    final visible = (!_expanded && needsCollapse)
        ? chips.take(limit).toList()
        : chips;
    final hidden = needsCollapse && !_expanded ? chips.length - limit : 0;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...visible,
        if (hidden > 0)
          ActionChip(
            label: Text('還有 $hidden 項'),
            onPressed: () => setState(() => _expanded = true),
          ),
        if (_expanded && needsCollapse)
          ActionChip(
            label: const Text('收合'),
            onPressed: () => setState(() => _expanded = false),
          ),
      ],
    );
  }
}
