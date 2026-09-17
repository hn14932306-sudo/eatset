import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/decision_engine.dart';
import '../widgets/decision_card.dart';
import '../widgets/mood_chips.dart';
import 'history_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    if (state.status == AppLoadStatus.loading && state.current == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('正在幫你決定這一餐…'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('吃定了'),
        actions: [
          IconButton(
            tooltip: '重新整理',
            onPressed: () => context.read<AppState>().refreshPlaces(),
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '歷史紀錄',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryScreen()),
              );
            },
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AppState>().refreshPlaces(),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Chip(
                  label: Text(state.mealSlot.labelZh),
                  avatar: const Icon(Icons.schedule, size: 18),
                ),
                const SizedBox(width: 8),
                if (state.isDemo)
                  Chip(
                    label: const Text('Demo'),
                    backgroundColor: scheme.tertiaryContainer,
                  ),
                if (!state.locationOk) ...[
                  const SizedBox(width: 8),
                  Chip(
                    label: const Text('未定位'),
                    backgroundColor: scheme.errorContainer,
                  ),
                ],
              ],
            ),
            if (state.statusNote != null) ...[
              const SizedBox(height: 8),
              Text(
                state.statusNote!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 16),
            Text('現在心情', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            MoodChips(
              value: state.prefs.mood,
              onChanged: (m) => context.read<AppState>().setMood(m),
            ),
            const SizedBox(height: 24),
            Text('這一餐就吃', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (state.current != null)
              DecisionCard(decision: state.current!)
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('暫時找不到合適選項'),
                      const SizedBox(height: 8),
                      Text(
                        '可取消部分排除，或稍後再試。App 不會停在空白頁。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () =>
                            context.read<AppState>().refreshPlaces(),
                        child: const Text('再試一次'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: state.current == null
                  ? null
                  : () => context.read<AppState>().confirmCurrent(),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('就吃這個'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: state.current == null || state.rerollsLeft <= 0
                  ? null
                  : () => context.read<AppState>().reroll(),
              icon: const Icon(Icons.casino_outlined),
              label: Text(
                state.rerollsLeft > 0
                    ? '換一個（今日剩 ${state.rerollsLeft}）'
                    : '今日重抽已用完（上限 ${DecisionEngine.dailyRerollLimit}）',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: state.current == null
                        ? null
                        : () => context.read<AppState>().excludeCurrentPlace(),
                    child: const Text('不要這家'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: state.current == null
                        ? null
                        : () => _showExcludeCategory(context, state),
                    child: const Text('不要這類'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showExcludeCategory(BuildContext context, AppState state) {
    final place = state.current?.place;
    if (place == null) return;
    final options = <String>{
      ...place.cuisineTags,
      if (place.name.contains('麵') || place.name.contains('面')) '麵',
      if (place.name.contains('飯') || place.name.contains('便當')) '飯',
      if (place.name.contains('火鍋')) '火鍋',
    }.toList();
    if (options.isEmpty) {
      options.addAll(['重口味', '清淡']);
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('排除哪一類？')),
              ...options.map(
                (c) => ListTile(
                  title: Text(c),
                  onTap: () {
                    Navigator.pop(ctx);
                    context.read<AppState>().excludeCategory(c);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
