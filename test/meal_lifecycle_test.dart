import 'dart:async';

import 'package:eatset/main.dart';
import 'package:eatset/models/meal_slot.dart';
import 'package:eatset/models/mood.dart';
import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shops = [
  Place(
    id: 'a',
    name: '甲店',
    lat: 25,
    lng: 121,
    rating: 4.5,
    userRatingsTotal: 100,
    priceLevel: 1,
    distanceMeters: 250,
  ),
  Place(
    id: 'b',
    name: '乙店',
    lat: 25,
    lng: 121,
    rating: 4.4,
    userRatingsTotal: 100,
    priceLevel: 1,
    distanceMeters: 350,
  ),
];

class ControlledStorage extends StorageService {
  Completer<void>? gate;
  final entered = Completer<void>();
  bool fail = false;
  int historyWrites = 0;
  int rerollWrites = 0;
  DateTime? savedDay;

  Future<void> beforeWrite() async {
    if (!entered.isCompleted) entered.complete();
    await gate?.future;
    if (fail) throw StateError('test storage failure');
  }

  @override
  Future<void> saveRerollCountToday(int count, {DateTime? day}) async {
    rerollWrites++;
    savedDay = day;
    await beforeWrite();
    await super.saveRerollCountToday(count, day: day);
  }

  @override
  Future<void> saveHistory(List<HistoryEntry> history) async {
    historyWrites++;
    await beforeWrite();
    await super.saveHistory(history);
  }
}

class FixedLocation extends LocationService {
  @override
  Future<LocationResult> getCurrentLocation() async =>
      const LocationResult.success(UserLocation(lat: 25, lng: 121));
}

class FixedPlaces extends PlacesService {
  @override
  Future<Place> fetchDetails(String id) async =>
      shops.firstWhere((p) => p.id == id);

  @override
  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = PlacesService.defaultRadiusMeters,
  }) async => const PlacesResult(
    places: shops,
    isDemo: false,
    usedDeviceLocation: true,
  );
}

AppState readyApp(DateTime Function() clock, {StorageService? storage}) {
  return AppState(
      now: clock,
      storageService: storage,
      placesService: FixedPlaces(),
    )
    ..status = AppLoadStatus.ready
    ..prefs = const UserPrefs(coldStartDone: true)
    ..nearby = shops
    ..current = const Decision(place: shopsFirst, reasonZh: '推薦', score: 1)
    ..isDemo = false
    ..locationOk = true;
}

const shopsFirst = Place(
  id: 'a',
  name: '甲店',
  lat: 25,
  lng: 121,
  rating: 4.5,
  userRatingsTotal: 100,
  priceLevel: 1,
  distanceMeters: 250,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'confirmation matches date and meal, including old entries without slot',
    () {
      final lunch = DateTime(2026, 9, 18, 12);
      final dinner = DateTime(2026, 9, 18, 18);
      final history = [
        HistoryEntry(
          placeId: 'd',
          placeName: '晚餐',
          confirmedAt: dinner,
          mealSlot: '晚餐',
        ),
        HistoryEntry(placeId: 'l', placeName: '午餐', confirmedAt: lunch),
      ];
      expect(latestConfirmedForMeal(history, lunch)!.placeId, 'l');
      expect(latestConfirmedForMeal(history, dinner)!.placeId, 'd');
      expect(
        latestConfirmedForMeal(history, DateTime(2026, 9, 19, 12)),
        isNull,
      );
    },
  );

  test(
    'lunch confirmation does not block dinner and meal switch keeps daily quota',
    () async {
      var now = DateTime(2026, 9, 18, 12);
      final app = readyApp(() => now)..rerollsUsedToday = 2;
      await app.confirmCurrent();
      expect(app.hasConfirmedMeal, isTrue);
      now = DateTime(2026, 9, 18, 18);
      await app.syncTime();
      expect(app.hasConfirmedMeal, isFalse);
      expect(app.mealSlot, MealSlot.dinner);
      expect(app.current!.mealSlot, '晚餐');
      expect(app.rerollsUsedToday, 2);
      await app.confirmCurrent();
      expect(app.history.map((h) => h.mealSlot), ['晚餐', '午餐']);
    },
  );

  test(
    'midnight resets quota even within late-night meal and before an action',
    () async {
      var now = DateTime(2026, 9, 18, 23, 59);
      final storage = StorageService();
      await storage.saveRerollCountToday(3, day: now);
      final app = readyApp(() => now, storage: storage)..rerollsUsedToday = 3;
      await app.confirmCurrent();
      now = DateTime(2026, 9, 19, 0, 1);
      await app.reroll();
      expect(app.hasConfirmedMeal, isFalse);
      expect(app.rerollsUsedToday, 1);
      expect(app.rerollsLeft, 2);
      expect(await storage.loadRerollCountToday(day: now), 1);
    },
  );

  test(
    'concurrent rerolls and confirmation cannot consume multiple slots',
    () async {
      final storage = ControlledStorage()..gate = Completer<void>();
      final app = readyApp(() => DateTime(2026, 9, 18, 12), storage: storage);
      final first = app.reroll();
      await storage.entered.future;
      expect(app.isBusy, isTrue);
      await app.reroll();
      expect(await app.confirmCurrent(), isNull);
      expect(await app.setMood(Mood.adventure), isFalse);
      storage.gate!.complete();
      await first;
      expect(app.rerollsUsedToday, 1);
      expect(storage.rerollWrites, 1);
      expect(app.history, isEmpty);
      expect(app.isBusy, isFalse);
    },
  );

  test(
    'confirmation is single-write while pending and after success',
    () async {
      final storage = ControlledStorage()..gate = Completer<void>();
      final app = readyApp(() => DateTime(2026, 9, 18, 12), storage: storage);
      final first = app.confirmCurrent();
      await storage.entered.future;
      expect(await app.confirmCurrent(), isNull);
      storage.gate!.complete();
      expect(await first, isNotNull);
      expect(await app.confirmCurrent(), isNull);
      expect(storage.historyWrites, 1);
      expect(app.history, hasLength(1));
    },
  );

  test(
    'failed writes release the lock and preserve quota/history for retry',
    () async {
      final storage = ControlledStorage()..fail = true;
      final app = readyApp(() => DateTime(2026, 9, 18, 12), storage: storage);
      await app.reroll();
      expect(app.current!.place.id, 'a');
      expect(app.rerollsUsedToday, 0);
      expect(app.isBusy, isFalse);
      expect(app.actionError, isNotNull);
      expect(await app.confirmCurrent(), isNull);
      expect(app.history, isEmpty);
      storage.fail = false;
      expect(await app.confirmCurrent(), isNotNull);
      expect(app.history, hasLength(1));
      expect(app.actionError, isNull);
    },
  );

  test(
    'an in-flight reroll is saved to its starting day, not the next day',
    () async {
      var now = DateTime(2026, 9, 18, 23, 59);
      final storage = ControlledStorage()..gate = Completer<void>();
      final app = readyApp(() => now, storage: storage);
      final first = app.reroll();
      await storage.entered.future;
      now = DateTime(2026, 9, 19, 0, 1);
      storage.gate!.complete();
      await first;
      expect(storage.savedDay, DateTime(2026, 9, 18, 23, 59));
      await app.syncTime();
      expect(app.rerollsUsedToday, 0);
      expect(await storage.loadRerollCountToday(day: now), 0);
    },
  );

  testWidgets('foreground timer and resume update the displayed meal', (
    tester,
  ) async {
    var now = DateTime(2026, 9, 18, 12);
    await StorageService().savePrefs(const UserPrefs(coldStartDone: true));
    final app = AppState(
      now: () => now,
      locationService: FixedLocation(),
      placesService: FixedPlaces(),
    );
    await tester.pumpWidget(EatSetApp(createAppState: () => app));
    await tester.pumpAndSettle();
    await app.confirmCurrent();
    await tester.pumpAndSettle();
    expect(find.text('午餐時間，先幫你挑好。'), findsOneWidget);
    expect(find.text('這餐，已經決定好了。'), findsOneWidget);
    now = DateTime(2026, 9, 18, 18);
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('午餐時間，先幫你挑好。'), findsNothing);
    expect(find.text('晚餐時間，先幫你挑好。'), findsOneWidget);
    expect(find.text('這餐，就從這家開始。'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = DateTime(2026, 9, 19, 8);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(app.mealSlot, MealSlot.breakfast);
    await tester.pumpWidget(const SizedBox());
  });
}
