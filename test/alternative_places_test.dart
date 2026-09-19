import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/models/meal_budget.dart';
import 'package:eatset/widgets/alternative_places.dart';
import 'package:eatset/screens/home_screen.dart';
import 'package:eatset/theme/eatset_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'meal_lifecycle_test.dart' as fixtures;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'alternatives obey filters, exclude current, and have stable order',
    () async {
      final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
      addTearDown(app.dispose);
      app.nearby = [
        ...fixtures.shops,
        const Place(
          id: 'hotel',
          name: 'Hotel 餐廳',
          lat: 25,
          lng: 121,
          priceLevel: 1,
        ),
        const Place(
          id: 'expensive',
          name: '高價',
          lat: 25,
          lng: 121,
          priceLevel: 4,
        ),
        const Place(
          id: 'closed',
          name: '休息',
          lat: 25,
          lng: 121,
          priceLevel: 1,
          openNow: false,
        ),
        const Place(
          id: 'excluded',
          name: '排除',
          lat: 25,
          lng: 121,
          priceLevel: 1,
        ),
      ];
      app.prefs = const UserPrefs(
        coldStartDone: true,
        mealBudget: MealBudget.economical,
        excludedPlaceIds: {'excluded'},
      );
      final ids = app.alternatives.map((p) => p.id).toList();
      expect(ids, isNotEmpty);
      expect(ids.length, lessThanOrEqualTo(2));
      expect(
        ids.any(['a', 'hotel', 'expensive', 'closed', 'excluded'].contains),
        isFalse,
      );
      expect(app.alternatives.map((p) => p.id), ids);
      expect(await app.selectAlternative('hotel'), isFalse);
      expect(app.current!.place.id, 'a');
    },
  );

  test(
    'selecting an alternative changes recommendation but not history or reroll count',
    () async {
      final storage = fixtures.ControlledStorage();
      final app = fixtures.readyApp(
        () => DateTime(2026, 9, 18, 12),
        storage: storage,
      );
      addTearDown(app.dispose);
      app.rerollsUsedToday = 3;
      final next = app.alternatives.first;
      expect(await app.selectAlternative(next.id), isTrue);
      expect(app.current!.place.id, next.id);
      expect(app.history, isEmpty);
      expect(storage.historyWrites, 0);
      expect(storage.rerollWrites, 0);
      expect(app.rerollsUsedToday, 3);
      await app.confirmCurrent();
      expect(app.alternatives, isEmpty);
      expect(await app.selectAlternative('a'), isFalse);
      expect(app.current!.place.id, next.id);
    },
  );

  test('meal skips are not shown again as alternatives', () async {
    final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
    addTearDown(app.dispose);
    await app.skipCurrentMeal();
    expect(app.alternatives.any((p) => p.id == 'a'), isFalse);
    expect(await app.selectAlternative('a'), isFalse);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'alternative card changes main recommendation at text scale $scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 700));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
        addTearDown(app.dispose);
        final next = app.alternatives.first;
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: app,
            child: MaterialApp(
              theme: EatSetTheme.light(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const HomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final nextName = find.descendant(
          of: find.byType(AlternativePlaces),
          matching: find.text(next.name),
        );
        await tester.scrollUntilVisible(
          nextName,
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(nextName);
        await tester.pumpAndSettle();
        expect(app.current!.place.id, next.id);
        expect(app.history, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
