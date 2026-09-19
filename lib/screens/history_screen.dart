import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/place.dart';
import '../providers/app_state.dart';
import '../services/decision_engine.dart';
import '../widgets/excluded_chips.dart';
import 'place_details_sheet.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.showExclusions = false,
    this.active = true,
    this.initialFavorites = false,
    this.showTabs = true,
  });
  final bool showExclusions;
  final bool active;
  final bool initialFavorites;
  final bool showTabs;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late bool _saved = widget.initialFavorites;
  final Set<String> _attempted = {};
  void _refreshVisible(AppState state) {
    if (!widget.active || widget.showExclusions) return;
    final places = _saved
        ? state.favorites
        : state.history
              .map((h) => h.place ?? Place.reference(h.placeId))
              .toList();
    final pending = places
        .take(5)
        .where(
          (p) =>
              !p.isDemo &&
              state.resolvePlace(p.id, fallback: p).needsRefresh &&
              _attempted.add(p.id),
        )
        .toList();
    if (pending.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (final p in pending) {
        if (!mounted || !widget.active) {
          _attempted.remove(p.id);
          continue;
        }
        try {
          await state.refreshPlace(p.id);
        } catch (_) {}
      }
    });
  }

  Widget _refreshControl(AppState state, Place place) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (state.placeErrors[place.id] != null)
        Text(state.placeErrors[place.id]!),
      TextButton.icon(
        onPressed: state.isRefreshingPlace(place.id)
            ? null
            : () => _save(() async {
                await state.refreshPlace(place.id, force: true);
              }, errorMessage: '更新失敗，請稍後再試'),
        icon: const Icon(Icons.refresh),
        label: Text(state.isRefreshingPlace(place.id) ? '正在更新店家資訊…' : '更新店家資訊'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (widget.showExclusions) return _exclusions(state);
    _refreshVisible(state);
    return Scaffold(
      appBar: AppBar(title: Text(_saved && !widget.showTabs ? '口袋收藏' : '餐點紀錄')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.showTabs)
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('最近決定'),
                  icon: Icon(Icons.history),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('收藏'),
                  icon: Icon(Icons.bookmark_outline),
                ),
              ],
              selected: {_saved},
              onSelectionChanged: (v) => setState(() => _saved = v.single),
            ),
          if (widget.showTabs) const SizedBox(height: 20),
          Text(
            _saved ? '留給下一次想吃的時候' : '決定過，不一定吃過',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(_saved ? '收藏不保證目前營業；出發前請確認店家資訊。' : '回報有沒有吃、喜不喜歡，下一次會更合口味。'),
          const SizedBox(height: 16),
          if (_saved && state.favorites.isEmpty)
            const _EmptyRecord(
              icon: Icons.bookmark_outline,
              title: '還沒有收藏',
              body: '在首頁店家卡片點「收藏」，下次就能在這裡找到。',
            ),
          if (!_saved && state.history.isEmpty)
            const _EmptyRecord(
              icon: Icons.restaurant_outlined,
              title: '還沒有紀錄',
              body: '按下「就吃這家」後會出現在這裡，吃完再回報感受。',
            ),
          if (_saved)
            ...state.favorites.map((saved) {
              final place = state.resolvePlace(saved.id, fallback: saved);
              return Card(
                child: ListTile(
                  title: Text(place.name),
                  subtitle: place.needsRefresh
                      ? _refreshControl(state, place)
                      : Text(place.priceLabel),
                  onTap: () => showPlaceDetails(context, place),
                  trailing: IconButton(
                    tooltip: '取消收藏',
                    icon: const Icon(Icons.bookmark),
                    onPressed: state.isBusy
                        ? null
                        : () => _save(() => state.toggleFavorite(place)),
                  ),
                ),
              );
            }),
          if (!_saved)
            ...state.history.map((entry) {
              final at = entry.confirmedAt.toLocal();
              final place = state.resolvePlace(
                entry.placeId,
                fallback: entry.place,
              );
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${at.month}/${at.day} · ${entry.mealSlot ?? '餐點'}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        place.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(entry.feedback.labelZh),
                      if (place.needsRefresh) _refreshControl(state, place),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: state.isBusy
                                ? null
                                : () => _feedback(entry),
                            child: Text(
                              entry.feedback == MealFeedback.planned
                                  ? '回報用餐'
                                  : '修改回饋',
                            ),
                          ),
                          TextButton(
                            onPressed: () => showPlaceDetails(context, place),
                            child: const Text('查看位置'),
                          ),
                          TextButton(
                            onPressed: state.isBusy
                                ? null
                                : () =>
                                      _save(() => state.toggleFavorite(place)),
                            child: Text(
                              state.isFavorite(place.id) ? '取消收藏' : '收藏',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _save(
    Future<void> Function() action, {
    String errorMessage = '儲存失敗，請再試一次',
  }) async {
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage)));
      }
    }
  }

  Future<void> _feedback(HistoryEntry entry) async {
    final value = await showModalBottomSheet<MealFeedback>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  context
                      .read<AppState>()
                      .resolvePlace(entry.placeId, fallback: entry.place)
                      .name,
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              ...MealFeedback.values.map(
                (feedback) => ListTile(
                  title: Text(feedback.labelZh),
                  selected: entry.feedback == feedback,
                  trailing: entry.feedback == feedback
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(ctx, feedback),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (value != null && mounted) {
      await _save(
        () => context.read<AppState>().recordFeedback(entry.id, value),
      );
    }
  }

  Widget _exclusions(AppState state) => Scaffold(
    appBar: AppBar(title: const Text('永久排除')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('這些店家與類別之後都不會推薦。只想這餐略過，請使用首頁「更多 → 這餐先跳過」。'),
        const SizedBox(height: 20),
        if (!state.hasExclusions)
          const _EmptyRecord(
            icon: Icons.check_circle_outline,
            title: '目前沒有永久排除',
            body: '你可以在店家卡片的「更多」設定。',
          ),
        ExcludedChipsWrap(
          chips: [
            ...state.prefs.excludedPlaceIds.map(
              (id) => InputChip(
                label: Text(state.labelForExcludedPlace(id)),
                onDeleted: state.isBusy
                    ? null
                    : () => _save(() => state.removeExcludedPlace(id)),
              ),
            ),
            ...state.prefs.excludedCategories.map(
              (cat) => InputChip(
                label: Text('類別：$cat'),
                onDeleted: state.isBusy
                    ? null
                    : () => _save(() => state.removeExcludedCategory(cat)),
              ),
            ),
          ],
        ),
        if (state.hasExclusions)
          TextButton(
            onPressed: state.isBusy
                ? null
                : () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('清除全部排除？'),
                        content: const Text('這些店家與類別會重新加入推薦候選。'),
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
                    if (ok == true) await _save(state.clearAllExclusions);
                  },
            child: const Text('清除全部排除'),
          ),
      ],
    ),
  );
}

class _EmptyRecord extends StatelessWidget {
  const _EmptyRecord({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36),
    child: Column(
      children: [
        Icon(icon, size: 40),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(body, textAlign: TextAlign.center),
      ],
    ),
  );
}
