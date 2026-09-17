import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final history = state.history;
    final prefs = state.prefs;
    final hasExclusions = state.hasExclusions;

    return Scaffold(
      appBar: AppBar(
        title: const Text('歷史與排除'),
        actions: [
          if (hasExclusions)
            TextButton(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('清除全部排除？'),
                    content: const Text('會取消所有「不要這家／不要這類」設定。'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('清除'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await context.read<AppState>().clearAllExclusions();
                }
              },
              child: const Text('全部清除'),
            ),
        ],
      ),
      body: ListView(
        children: [
          if (hasExclusions)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已排除', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '點芯片上的 × 可取消單一排除',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ...prefs.excludedCategories.map(
                        (c) => InputChip(
                          label: Text('類別：$c'),
                          onDeleted: () => context
                              .read<AppState>()
                              .removeExcludedCategory(c),
                          deleteButtonTooltipMessage: '取消排除',
                        ),
                      ),
                      ...prefs.excludedPlaceIds.map(
                        (id) => InputChip(
                          label: Text(state.labelForExcludedPlace(id)),
                          onDeleted: () =>
                              context.read<AppState>().removeExcludedPlace(id),
                          deleteButtonTooltipMessage: '取消排除',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('目前沒有排除項目'),
                subtitle: Text('在首頁「更多」可排除店家或類別'),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('確認過的餐點',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (history.isEmpty)
            const ListTile(
              title: Text('還沒有紀錄'),
              subtitle: Text('按下「就吃這個」後會出現在這裡'),
            )
          else
            ...history.map((h) {
              final local = h.confirmedAt.toLocal();
              final stamp =
                  '${local.month}/${local.day} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
              return ListTile(
                leading: const Icon(Icons.restaurant),
                title: Text(h.placeName),
                subtitle: Text(
                  [
                    if (h.mealSlot != null) h.mealSlot!,
                    stamp,
                    if (h.cuisineTags.isNotEmpty) h.cuisineTags.join('・'),
                  ].join(' · '),
                ),
              );
            }),
        ],
      ),
    );
  }
}
