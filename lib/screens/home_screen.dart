import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../services/decision_engine.dart';
import '../widgets/decision_card.dart';
import '../widgets/mood_chips.dart';
import 'confirm_screen.dart';
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
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (state.isDemo || !state.locationOk)
              _StatusBanner(state: state),
            if (state.isDemo || !state.locationOk) const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: Text(state.mealSlot.labelZh),
                avatar: const Icon(Icons.schedule, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(height: 20),
            Text('這一餐就吃', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (state.current != null)
              DecisionCard(
                decision: state.current!,
                showRealDistance: state.showRealDistance,
              )
            else
              _EmptyDecisionCard(state: state),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: state.current == null
                  ? null
                  : () => _onConfirm(context),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('就吃這個'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: state.current == null || state.rerollsLeft <= 0
                  ? null
                  : () => context.read<AppState>().reroll(),
              icon: const Icon(Icons.shuffle),
              label: Text(
                state.rerollsLeft > 0
                    ? '換一個 · 今日剩 ${state.rerollsLeft}'
                    : '今日已換完（上限 ${DecisionEngine.dailyRerollLimit}）',
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
            if (state.rerollsLeft <= 0 && state.current != null) ...[
              const SizedBox(height: 6),
              Text(
                '明天再換；或微調心情後仍會重算',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: _MoodTuneDisclosure()),
                TextButton.icon(
                  onPressed: state.current == null
                      ? null
                      : () => _showMoreActions(context, state),
                  icon: const Icon(Icons.more_horiz, size: 20),
                  label: const Text('更多'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onConfirm(BuildContext context) async {
    final app = context.read<AppState>();
    final place = await app.confirmCurrent();
    if (place == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConfirmScreen(
          place: place,
          isDemo: app.isDemo || place.isDemo,
        ),
      ),
    );
  }

  void _showMoreActions(BuildContext context, AppState state) {
    final category = state.inferCategoryForCurrent();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('更多'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('不要這家'),
                subtitle: const Text('之後不再推薦這一家'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final placeId = state.current?.place.id;
                  final name =
                      await context.read<AppState>().excludeCurrentPlace();
                  if (!context.mounted || name == null) return;
                  _showUndoSnackBar(
                    context,
                    message: '已排除「$name」',
                    onUndo: placeId == null
                        ? null
                        : () => context
                            .read<AppState>()
                            .removeExcludedPlace(placeId),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('不要這類'),
                subtitle: Text(
                  category == null
                      ? '排除系統判斷的這一類'
                      : '排除系統判斷的「$category」',
                ),
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
          content: Text('之後少推「$category」這類店家？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('先不要'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final cat =
                    await context.read<AppState>().excludeCategory(category);
                if (!context.mounted || cat == null) return;
                _showUndoSnackBar(
                  context,
                  message: '之後少推「$cat」',
                  onUndo: () =>
                      context.read<AppState>().removeExcludedCategory(cat),
                );
              },
              child: const Text('排除'),
            ),
          ],
        );
      },
    );
  }

  void _showUndoSnackBar(
    BuildContext context, {
    required String message,
    Future<void> Function()? onUndo,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        action: onUndo == null
            ? null
            : SnackBarAction(
                label: '復原',
                onPressed: () {
                  onUndo();
                },
              ),
      ),
    );
  }
}

/// Demo／未定位誠實橫幅（設計 §5）：單一橫幅，可合併兩種狀態。
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final String title;
    final String? subtitle;
    final bool showLocateCta = !state.locationOk;

    if (!state.locationOk) {
      bg = state.isDemo ? scheme.tertiaryContainer : scheme.errorContainer;
      title = '需要定位才能找附近餐廳';
      subtitle = state.isDemo ? '目前先用示範店家 · 何時開定位都可以' : null;
    } else if (state.isDemo) {
      bg = scheme.tertiaryContainer;
      title = '示範模式 · 非你附近的真實店家';
      subtitle = '開定位與 API 後會改推附近餐廳';
    } else {
      bg = scheme.errorContainer;
      title = '需要定位才能找附近餐廳';
      subtitle = null;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            if (showLocateCta) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () => context.read<AppState>().refreshPlaces(),
                  child: const Text('開啟定位'),
                ),
              ),
            ],
          ],
        ),
      ),
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
            const Text('暫時沒有合適選項'),
            const SizedBox(height: 8),
            Text(
              state.hasExclusions
                  ? '可解除部分排除，或稍後再試'
                  : '稍後再試，或下拉重新整理。',
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
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              child: const Text('管理排除'),
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
