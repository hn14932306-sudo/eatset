import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/meal_budget.dart';
import '../models/search_range.dart';
import '../providers/app_state.dart';

class DiningFiltersButton extends StatelessWidget {
  const DiningFiltersButton({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final prefs = app.prefs;
    return ActionChip(
      avatar: const Icon(Icons.tune, size: 18),
      // The range only appears once it differs from the default.
      label: Text(
        '價格：${prefs.mealBudget.labelZh}'
        '${prefs.maxDistanceMeters == SearchRange.defaultMeters ? '' : ' · ${SearchRange.label(prefs.maxDistanceMeters)}'}',
      ),
      onPressed: app.isBusy
          ? null
          : () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => ChangeNotifierProvider.value(
                value: context.read<AppState>(),
                child: const _DiningFiltersSheet(),
              ),
            ),
    );
  }
}

class _DiningFiltersSheet extends StatefulWidget {
  const _DiningFiltersSheet();

  @override
  State<_DiningFiltersSheet> createState() => _DiningFiltersSheetState();
}

class _DiningFiltersSheetState extends State<_DiningFiltersSheet> {
  late MealBudget _budget;
  late bool _hotels;
  late bool _unknown;
  late int _range;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final prefs = context.read<AppState>().prefs;
    _budget = prefs.mealBudget;
    _hotels = prefs.includeHotelRestaurants;
    _unknown = prefs.includeUnknownPrices;
    _range = prefs.maxDistanceMeters;
  }

  @override
  Widget build(BuildContext context) {
    final busy = _saving || context.watch<AppState>().isBusy;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('這餐的價格、距離與店家', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: MealBudget.values
                  .map(
                    (budget) => ChoiceChip(
                      label: Text(budget.labelZh),
                      selected: _budget == budget,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _budget = budget),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            const Text(r'省錢：$ 以下；日常：$$ 以下；不限：所有價格等級。'),
            const SizedBox(height: 4),
            const Text('價格等級僅供參考，不代表固定人均金額；實際價格請確認菜單。'),
            const SizedBox(height: 20),
            Text('距離', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SearchRange.options
                  .map(
                    (meters) => ChoiceChip(
                      key: Key('range_$meters'),
                      label: Text(SearchRange.label(meters)),
                      selected: _range == meters,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _range = meters),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            const Text('以直線距離計算，不代表實際步行路程。放寬距離時會重新查詢附近店家。'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包含飯店餐廳'),
              subtitle: const Text('依住宿類型與店名辨識，可能有遺漏'),
              value: _hotels,
              onChanged: _saving ? null : (v) => setState(() => _hotels = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包含價格未知的店家'),
              subtitle: const Text('有預算時，優先推薦價格已知的店家'),
              value: _unknown,
              onChanged: _saving ? null : (v) => setState(() => _unknown = v),
            ),
            if (_error != null) Text(_error!),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: busy ? null : _apply,
              child: Text(_saving ? '套用中…' : '套用並重新推薦'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _apply() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AppState>().setDiningFilters(
        budget: _budget,
        includeHotels: _hotels,
        includeUnknownPrices: _unknown,
        maxDistanceMeters: _range,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '套用失敗，請再試一次';
        });
      }
    }
  }
}
