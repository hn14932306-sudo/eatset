import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_state.dart';
import '../models/meal_budget.dart';
import '../models/place.dart';
import '../screens/place_details_sheet.dart';
import '../widgets/alternative_places.dart';
import '../widgets/place_links.dart';
import '../services/decision_engine.dart';
import '../widgets/decision_card.dart';
import '../widgets/dining_filters.dart';
import '../widgets/excluded_chips.dart';
import '../widgets/mood_chips.dart';
import 'confirm_screen.dart';
import 'history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final app = context.read<AppState>();
      if (!app.showDefaultMoodHint) return;
      app.consumeDefaultMoodHint();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('先用「想穩妥」幫你挑；下方可改心情'),
          duration: Duration(seconds: 3),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;
    final confirmed = state.hasConfirmedMeal;

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
        actions: const [DiningFiltersButton(), SizedBox(width: 12)],
        // A thin bar in the app bar: updating no longer pushes the card down.
        bottom: state.status == AppLoadStatus.loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  semanticsLabel: '正在更新附近店家，先保留目前推薦',
                ),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<AppState>().refreshPlacesUnlessRecent(),
        child: ListView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          children: [
            if (state.offline && !state.isDemo && !confirmed) ...[
              _OfflineBanner(state: state),
              const SizedBox(height: 12),
            ],
            if (state.isDemo || !state.locationOk) _StatusBanner(state: state),
            if (state.isDemo || !state.locationOk) const SizedBox(height: 12),
            Text(
              '${state.mealSlot.labelZh}時間，先幫你挑好。',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              confirmed ? '這餐，已經決定好了。' : '這餐，就從這家開始。',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            _BudgetSelector(state: state),
            const SizedBox(height: 16),
            if (state.actionError != null) ...[
              Text(state.actionError!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 8),
            ],
            if (confirmed)
              _ConfirmedMealCard(state: state)
            else if (state.current != null)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: KeyedSubtree(
                  key: ValueKey(state.current!.place.id),
                  child: DecisionCard(
                    decision: state.current!,
                    homePresentation: true,
                    offline: state.offline,
                    showRealDistance: state.showRealDistance,
                    isFavorite: state.isFavorite(state.current!.place.id),
                    onFavorite: state.isBusy
                        ? null
                        : () => _toggleFavorite(state),
                  ),
                ),
              )
            else
              _EmptyDecisionCard(state: state),
            const SizedBox(height: 14),
            _actions(context, state),
            if (!confirmed && state.current != null)
              TextButton.icon(
                onPressed: state.rerollsLeft <= 0 || state.isBusy
                    ? null
                    : state.reroll,
                icon: const Icon(Icons.shuffle, size: 18),
                label: Text(
                  state.rerollsLeft > 0
                      ? '再幫我挑 · 今日剩 ${state.rerollsLeft}'
                      : '今日已換完（上限 ${DecisionEngine.dailyRerollLimit}）',
                ),
              ),
            if (!confirmed && state.current != null)
              PlaceLinks(place: state.current!.place),
            if (!confirmed)
              AlternativePlaces(
                places: state.alternatives,
                showRealDistance: state.showRealDistance,
                busy: state.isBusy,
                offline: state.offline,
                onSelect: (place) => _selectAlternative(state, place),
              ),
            if (state.skippedThisMealCount > 0)
              TextButton.icon(
                onPressed: state.isBusy ? null : () => state.restoreMealSkips(),
                icon: const Icon(Icons.undo),
                label: Text('這餐已略過 ${state.skippedThisMealCount} 家 · 還原'),
              ),
            if (!confirmed && state.hasPendingUndo) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('undo_excluded_place'),
                  onPressed: state.isBusy
                      ? null
                      : () {
                          unawaited(
                            context.read<AppState>().undoLastExcludedPlace(),
                          );
                        },
                  icon: const Icon(Icons.undo, size: 18),
                  label: Text('復原「${state.pendingUndoPlace!.name}」'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(child: _MoodTuneDisclosure()),
                if (!confirmed)
                  TextButton.icon(
                    onPressed: state.current == null || state.isBusy
                        ? null
                        : () => _showMoreActions(context, state),
                    icon: const Icon(Icons.more_horiz, size: 20),
                    label: const Text('更多'),
                  ),
              ],
            ),
            // Google Places 政策：顯示真實 Places 資料時須標示來源；Demo 不聲稱來自 Google。
            if (!state.isDemo) ...[
              const SizedBox(height: 28),
              Text(
                '店家資料來自 Google',
                key: const Key('places_attribution'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context, AppState state) {
    if (state.hasConfirmedMeal) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: () => _openConfirmedMaps(context, state),
            icon: const Icon(Icons.map_outlined),
            label: const Text('開啟地圖'),
          ),
          TextButton(
            onPressed: state.isBusy ? null : state.requestRedecide,
            child: const Text('想換一家'),
          ),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final confirm = FilledButton.icon(
          onPressed: state.current == null || state.isBusy
              ? null
              : () => _onConfirm(context),
          label: const Text('就吃這家'),
          icon: const Icon(Icons.arrow_outward, size: 18),
        );
        final details = OutlinedButton(
          onPressed: state.current == null || state.isBusy
              ? null
              : () => showPlaceDetails(context, state.current!.place),
          child: const Text('詳情'),
        );
        if (MediaQuery.textScalerOf(context).scale(14) > 24) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [confirm, const SizedBox(height: 8), details],
          );
        }
        return Row(
          children: [
            Expanded(child: confirm),
            const SizedBox(width: 10),
            details,
          ],
        );
      },
    );
  }

  Future<void> _selectAlternative(AppState state, Place place) async {
    final changed = await state.selectAlternative(place.id);
    if (changed && mounted && _scroll.hasClients) {
      await _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _toggleFavorite(AppState state) async {
    final place = state.current?.place;
    if (place == null) return;
    try {
      await state.toggleFavorite(place);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('收藏儲存失敗，請再試一次')));
      }
    }
  }

  Future<void> _onConfirm(BuildContext context) async {
    final app = context.read<AppState>();
    final place = await app.confirmCurrent();
    if (place == null || !context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ConfirmScreen(place: place, isDemo: app.isDemo || place.isDemo),
      ),
    );
  }

  Future<void> _openConfirmedMaps(BuildContext context, AppState state) async {
    final place = state.placeForConfirmedMeal();
    if (place == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ConfirmScreen(place: place, isDemo: state.isDemo || place.isDemo),
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
                leading: const Icon(Icons.skip_next_outlined),
                title: const Text('這餐先跳過'),
                subtitle: const Text('這一餐不再出現，下個餐段恢復；不扣換店次數'),
                onTap: () async {
                  Navigator.pop(ctx);
                  try {
                    await context.read<AppState>().skipCurrentMeal();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('略過失敗，請再試一次')),
                      );
                    }
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.block_outlined),
                title: const Text('不要這家'),
                subtitle: const Text('永久排除；可在「我的」解除'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final app = context.read<AppState>();
                  if (app.current == null) return;
                  final name = await app.excludeCurrentPlace();
                  if (!context.mounted || name == null) return;
                  _showUndoSnackBar(
                    context,
                    message: '已排除「$name」',
                    onUndo: () {
                      // 用排除當下捕獲的 AppState；Web 上 SnackBarAction 常不觸發，
                      // Home 另有持久復原按鈕走同一 undoLastExcludedPlace。
                      unawaited(app.undoLastExcludedPlace());
                    },
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: const Text('不要這類'),
                subtitle: Text(
                  category == null ? '排除系統判斷的這一類' : '排除系統判斷的「$category」',
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('無法判斷這家的類別，請改用「不要這家」。')));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('不要這類？'),
          content: Text('之後不再推薦「$category」這類店家？可在「我的」解除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('先不要'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final app = context.read<AppState>();
                final cat = await app.excludeCategory(category);
                if (!context.mounted || cat == null) return;
                _showUndoSnackBar(
                  context,
                  message: '已永久排除「$cat」',
                  onUndo: () {
                    app.removeExcludedCategory(cat);
                  },
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
    required VoidCallback onUndo,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '復原',
          // sync VoidCallback：kick off Future，不依賴 async tear-off。
          // Flutter Web 上 SnackBarAction 常不觸發；Home 另有持久復原按鈕。
          onPressed: onUndo,
        ),
      ),
    );
  }
}

/// 這餐已決定：顯示確認店名（非重新決策主路徑）。
class _ConfirmedMealCard extends StatelessWidget {
  const _ConfirmedMealCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entry = state.mealConfirmed!;
    final place = state.placeForConfirmedMeal();
    final decision = state.current?.place.id == entry.placeId
        ? state.current
        : null;

    if (decision != null) {
      return DecisionCard(
        decision: decision,
        homePresentation: true,
        showRealDistance: state.showRealDistance,
      );
    }

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              place?.name ?? entry.placeName,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '這餐已確認，不用再糾結',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// No connection: what is already loaded still works, and this says so instead
/// of leaving the user to wonder why nothing updates.
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      key: const Key('offline_banner'),
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: scheme.onSecondaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '目前沒有網路連線',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '先顯示已載入的店家；評分與營業狀態可能不是最新。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: state.isBusy ? null : () => state.refreshPlaces(),
              child: const Text('重新連線'),
            ),
          ],
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
      subtitle = state.locationHelpSubtitle;
    } else if (state.isDemo) {
      bg = scheme.tertiaryContainer;
      title = '示範模式 · 非你附近的真實店家';
      // Places 失敗／無金鑰時的 noteZh 會進 statusNote；有則顯示具體原因。
      subtitle =
          (state.statusNote != null && state.statusNote!.trim().isNotEmpty)
          ? state.statusNote
          : '開定位與 API 後會改推附近餐廳';
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
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (showLocateCta) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonal(
                  onPressed: () => context.read<AppState>().enableLocation(),
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
                  ? '可調整上方價格條件、解除部分排除，或稍後再試'
                  : '可調整上方價格條件，或下拉重新整理。',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (state.hasExclusions) ...[
              ExcludedChipsWrap(
                chips: [
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
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const HistoryScreen(showExclusions: true),
                        ),
                      );
                    },
                    child: const Text('管理排除'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => state.refreshPlaces(),
                    child: const Text('再試一次'),
                  ),
                ),
              ],
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
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        subtitle: Text(
          state.prefs.mood.labelZh,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.outline),
        ),
        children: [
          MoodChips(
            value: state.prefs.mood,
            onChanged: (m) async {
              final app = context.read<AppState>();
              final changed = await app.setMood(m);
              if (!context.mounted || !changed) return;
              if (app.showMoodReselectedHint) {
                app.consumeMoodReselectedHint();
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已依心情重新決定'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _BudgetSelector extends StatelessWidget {
  const _BudgetSelector({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: SegmentedButton<MealBudget>(
      showSelectedIcon: false,
      segments: MealBudget.values
          .map((b) => ButtonSegment(value: b, label: Text(b.labelZh)))
          .toList(),
      selected: {state.prefs.mealBudget},
      onSelectionChanged: state.isBusy
          ? null
          : (values) async {
              try {
                await state.setDiningFilters(
                  budget: values.single,
                  includeHotels: state.prefs.includeHotelRestaurants,
                  includeUnknownPrices: state.prefs.includeUnknownPrices,
                );
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('預算儲存失敗，請再試一次')));
                }
              }
            },
    ),
  );
}
