import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = context.watch<AppState>().history;
    final prefs = context.watch<AppState>().prefs;

    return Scaffold(
      appBar: AppBar(title: const Text('歷史與排除')),
      body: ListView(
        children: [
          if (prefs.excludedPlaceIds.isNotEmpty ||
              prefs.excludedCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('已排除', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ...prefs.excludedCategories.map(
                        (c) => Chip(label: Text('類別：$c')),
                      ),
                      ...prefs.excludedPlaceIds.take(10).map(
                            (id) => Chip(label: Text('店：$id')),
                          ),
                    ],
                  ),
                ],
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
