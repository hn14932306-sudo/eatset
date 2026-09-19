import 'dart:math';

import 'package:eatset/models/meal_budget.dart';
import 'package:eatset/models/meal_slot.dart';
import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/screens/home_screen.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Place shop(
  String name, {
  int? price,
  List<String> types = const ['restaurant'],
}) => Place(
  id: name,
  name: name,
  lat: 25,
  lng: 121,
  priceLevel: price,
  types: types,
  rating: 4.6,
  userRatingsTotal: 500,
  openNow: true,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('default filters high prices and hotels, preserves ordinary 飯店', () {
    final places = [
      shop('家常飯店', price: 1),
      shop('聚餐餐廳', price: 2),
      shop('高級餐廳', price: 3),
      shop('昂貴餐廳', price: 4),
      shop('住宿附設餐廳', price: 1, types: ['restaurant', 'lodging']),
      shop('台北大飯店餐廳', price: 1),
      shop('Example Hotel 餐廳', price: 1),
      shop('Hotel California 麵店', price: 1),
      shop('價格未知小店'),
    ];
    final result = DecisionEngine().filterCandidates(places, const UserPrefs());
    expect(result.map((p) => p.name), ['家常飯店', '聚餐餐廳', '價格未知小店']);
    final all = DecisionEngine().filterCandidates(
      places,
      const UserPrefs(
        mealBudget: MealBudget.any,
        includeHotelRestaurants: true,
      ),
    );
    expect(all, hasLength(places.length));
  });

  test('economical ceiling and unknown exclusion never silently relax', () {
    final engine = DecisionEngine();
    final prefs = const UserPrefs(
      mealBudget: MealBudget.economical,
      includeUnknownPrices: false,
    );
    expect(
      engine.decide(
        [shop('中價', price: 2), shop('未知'), shop('壞資料', price: 8)],
        prefs,
        mealSlot: MealSlot.lunch,
      ),
      isNull,
    );
    expect(
      engine.filterCandidates([
        shop('免費', price: 0),
        shop('平價', price: 1),
      ], prefs),
      hasLength(2),
    );
  });

  test('unknown price is fallback and never described as cheap', () {
    final engine = DecisionEngine(random: Random(42));
    final unknown = shop('未知');
    final known = shop('平價', price: 1);
    expect(
      engine
          .decide(
            [unknown, known],
            const UserPrefs(),
            mealSlot: MealSlot.lunch,
          )!
          .place,
      known,
    );
    expect(
      engine
          .decide([unknown], const UserPrefs(), mealSlot: MealSlot.lunch)!
          .place,
      unknown,
    );
    expect(unknown.priceLabel, contains('價格未知'));
    expect(shop('無效', price: -1).knownPriceLevel, isNull);
  });

  test(
    'new preferences migrate and persist through copies and storage',
    () async {
      expect(UserPrefs.fromJson({}).mealBudget, MealBudget.everyday);
      expect(
        UserPrefs.fromJson({'budgetSensitive': true}).mealBudget,
        MealBudget.economical,
      );
      final prefs = UserPrefs.fromJson({'mealBudget': 'future'}).copyWith(
        mealBudget: MealBudget.any,
        includeHotelRestaurants: true,
        includeUnknownPrices: false,
      );
      await StorageService().savePrefs(prefs.copyWith(prefersLight: true));
      final restored = await StorageService().loadPrefs();
      expect(restored.mealBudget, MealBudget.any);
      expect(restored.includeHotelRestaurants, isTrue);
      expect(restored.includeUnknownPrices, isFalse);
    },
  );

  testWidgets('home filter applies, persists, shows price and empty recovery', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppState();
    app.status = AppLoadStatus.ready;
    app.prefs = const UserPrefs(coldStartDone: true);
    app.nearby = [shop('中價餐廳', price: 2)];
    app.current = Decision(place: app.nearby.first, reasonZh: '推薦', score: 1);
    app.locationOk = true;
    app.isDemo = false;
    app.rerollsUsedToday = 2;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    expect(find.text(r'$$ · 中等'), findsOneWidget);
    await tester.tap(find.text('價格：日常'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('省錢').last);
    await tester.tap(find.text('套用並重新推薦'));
    await tester.pumpAndSettle();
    expect(app.current, isNull);
    expect(app.rerollsUsedToday, 2);
    expect(
      (await StorageService().loadPrefs()).mealBudget,
      MealBudget.economical,
    );
    expect(find.text('價格：省錢'), findsOneWidget);
    expect(find.text('暫時沒有合適選項'), findsOneWidget);
    await tester.tap(find.text('價格：省錢'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常').last);
    await tester.tap(find.text('套用並重新推薦'));
    await tester.pumpAndSettle();
    expect(app.current!.place.name, '中價餐廳');
    expect(find.text(r'$$ · 中等'), findsOneWidget);
    await tester.tap(find.text('價格：日常'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不限').last);
    await tester.tap(find.text('包含飯店餐廳'));
    await tester.tap(find.text('包含價格未知的店家'));
    await tester.tap(find.text('套用並重新推薦'));
    await tester.pumpAndSettle();
    final saved = await StorageService().loadPrefs();
    expect(saved.mealBudget, MealBudget.any);
    expect(saved.includeHotelRestaurants, isTrue);
    expect(saved.includeUnknownPrices, isFalse);
    expect(tester.takeException(), isNull);
  });
}
