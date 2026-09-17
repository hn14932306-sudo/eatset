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
            tooltip: '歷史與排除',
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
            const SizedBox(height: 20),
            Text('這一餐就吃', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (state.current != null)
              DecisionCard(decision: state.current!)
            else
              _EmptyDecisionCard(state: state),
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
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: state.current == null
                    ? null
                    : () => _showMoreActions(context, state),
                icon: const Icon(Icons.more_horiz, size: 20),
                label: const Text('更多'),
              ),
            ),
            const SizedBox(height: 8),
            const _MoodTuneDisclosure(),
          ],
        ),
      ),
    );
  }

  void _showMoreActions(BuildContext context, AppState state) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('不要這家'),
                subtitle: const Text('之後不再推薦這一家'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.read<AppState>().excludeCurrentPlace();
                },
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('不要這類'),
                subtitle: const Text('排除系統推斷的這一類'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmExcludeCategory(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _confirmExcludeCategory(BuildContext context) {
    final state = context.read<AppState>();
    final category = state.inferCategoryForCurrent();
    if (category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法判斷這家的類別，請改用「不要這家」。')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('不要這類？'),
          content: Text('要排除「$category」這類餐廳嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('否'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<AppState>().excludeCategory(category);
              },
              child: const Text('是'),
            ),
          ],
        );
      },
    );
  }
}

class _EmptyDecisionCard extends StatelessWidget {
  const _EmptyDecisionCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Text('暫時找不到合適選項'),
            const SizedBox(height: 8),
            Text(
              state.hasExclusions
                  ? '可取消部分排除，或稍後再試。'
                  : '稍後再試，或下拉重新整理。App 不會停在空白頁。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (state.hasExclusions) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ...state.prefs.excludedCategories.map(
                    (c) => InputChip(
                      label: Text('類別：$c'),
                      onDeleted: () =>
                          context.read<AppState>().removeExcludedCategory(c),
                    ),
                  ),
                  ...state.prefs.excludedPlaceIds.map(
                    (id) => InputChip(
                      label: Text(state.labelForExcludedPlace(id)),
                      onDeleted: () =>
                          context.read<AppState>().removeExcludedPlace(id),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => context.read<AppState>().clearAllExclusions(),
                child: const Text('清除全部排除'),
              ),
              const SizedBox(height: 4),
            ],
            FilledButton(
              onPressed: () => context.read<AppState>().refreshPlaces(),
              child: const Text('再試一次'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              child: const Text('管理排除項目'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 心情微調：預設收合，不與主 CTA 搶視覺層級。
class _MoodTuneDisclosure extends StatelessWidget {
  const _MoodTuneDisclosure();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          '微調心情',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        subtitle: Text(
          state.prefs.mood.labelZh,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.outline,
              ),
        ),
        children: [
          MoodChips(
            value: state.prefs.mood,
            onChanged: (m) => context.read<AppState>().setMood(m),
            compact: true,
          ),
        ],
      ),
    );
  }
}
