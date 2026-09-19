import 'dart:math';

import 'package:eatset/models/meal_slot.dart';
import 'package:eatset/models/mood.dart';
import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meal_lifecycle_test.dart' as fixtures;

class CountingLocation extends LocationService {
  int calls = 0;
  @override
  Future<LocationResult> getCurrentLocation() async {
    calls++;
    return const LocationResult.failure(LocationFailureReason.denied);
  }
}

class FailingPlaces extends PlacesService {
  @override
  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = PlacesService.defaultRadiusMeters,
  }) async => throw StateError('offline');
}

class FailingStorage extends StorageService {
  @override
  Future<void> savePrefs(UserPrefs prefs) async => throw StateError('disk');
  @override
  Future<void> saveFavorites(List<Place> places) async =>
      throw StateError('disk');
  @override
  Future<void> saveMealSkips(String key, Set<String> ids) async =>
      throw StateError('disk');
  @override
  Future<void> saveHistory(List<HistoryEntry> history) async =>
      throw StateError('disk');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('onboarding remains recoverable when preference saving fails', () async {
    final app = AppState(storageService: FailingStorage())
      ..status = AppLoadStatus.ready;
    await expectLater(app.skipColdStart(), throwsStateError);
    expect(app.prefs.coldStartDone, isFalse);
    await expectLater(
      app.completeColdStart({'carb': true, 'flavor': false, 'mood': false}),
      throwsStateError,
    );
    expect(app.prefs.coldStartDone, isFalse);
    expect(app.prefs.prefersNoodles, isNull);
    expect(app.isBusy, isFalse);
  });

  test('old and unknown feedback stays unreported; snapshots round trip', () {
    final old = {
      'placeId': 'a',
      'placeName': '甲店',
      'confirmedAt': '2026-09-18T12:00:00',
    };
    expect(HistoryEntry.fromJson(old).feedback, MealFeedback.planned);
    expect(
      HistoryEntry.fromJson({...old, 'feedback': 'future'}).feedback,
      MealFeedback.planned,
    );
    final entry = HistoryEntry(
      placeId: 'a',
      placeName: '甲店',
      confirmedAt: DateTime(2026, 9, 18, 12),
      place: fixtures.shopsFirst,
      feedback: MealFeedback.liked,
    );
    final loaded = HistoryEntry.fromJson(entry.toJson());
    expect(loaded.id, entry.id);
    expect(loaded.feedback, MealFeedback.liked);
    expect(loaded.place!.priceLevel, 1);
  });

  test(
    'confirmation stores a plan and feedback survives reload; not eaten allows a new decision',
    () async {
      final at = DateTime(2026, 9, 18, 12);
      final app = fixtures.readyApp(() => at);
      await app.confirmCurrent();
      final entry = app.history.single;
      expect(entry.feedback, MealFeedback.planned);
      expect(entry.place!.name, '甲店');
      await app.recordFeedback(entry.id, MealFeedback.liked);
      expect(
        (await StorageService().loadHistory()).single.feedback,
        MealFeedback.liked,
      );
      await app.recordFeedback(entry.id, MealFeedback.notEaten);
      expect(app.hasConfirmedMeal, isFalse);
      expect(app.history, hasLength(1));
      expect(app.current, isNotNull);
    },
  );

  test(
    'unreported and not-eaten history do not affect exploration or preference score',
    () {
      final now = DateTime(2026, 9, 18, 12);
      double score(MealFeedback? feedback) =>
          DecisionEngine(random: Random(1)).scorePlace(
            fixtures.shopsFirst,
            const UserPrefs(mood: Mood.adventure),
            mealSlot: MealSlot.lunch,
            recentHistory: feedback == null
                ? []
                : [
                    HistoryEntry(
                      placeId: 'a',
                      placeName: '甲店',
                      confirmedAt: now,
                      feedback: feedback,
                    ),
                  ],
          );
      expect(score(MealFeedback.planned), score(null));
      expect(score(MealFeedback.notEaten), score(null));
      expect(score(MealFeedback.disliked), lessThan(score(MealFeedback.liked)));
      expect(score(MealFeedback.neutral), lessThan(score(null)));
    },
  );

  test('balance reminder counts only eaten meals', () {
    final now = DateTime(2026, 9, 18, 12);
    final planned = List.generate(
      4,
      (i) => HistoryEntry(
        placeId: '$i',
        placeName: '麻辣火鍋',
        confirmedAt: now.subtract(Duration(days: i)),
        cuisineTags: ['重口味'],
      ),
    );
    final engine = DecisionEngine();
    expect(
      engine.shouldOfferBalanceNudge(
        history: planned,
        now: now,
        lastBalanceNudgeAt: null,
      ),
      isFalse,
    );
    expect(
      engine.shouldOfferBalanceNudge(
        history: planned
            .map((h) => h.withFeedback(MealFeedback.neutral))
            .toList(),
        now: now,
        lastBalanceNudgeAt: null,
      ),
      isTrue,
    );
  });

  test(
    'meal skips persist through restart and filters, never consume quota; new meal restores candidates',
    () async {
      var now = DateTime(2026, 9, 18, 12);
      final storage = StorageService();
      final app = fixtures.readyApp(() => now)..rerollsUsedToday = 2;
      await storage.savePrefs(app.prefs);
      await storage.saveRerollCountToday(2, day: now);
      await app.skipCurrentMeal();
      expect(app.current!.place.id, 'b');
      expect(app.rerollsUsedToday, 2);
      expect(app.prefs.excludedPlaceIds, isEmpty);
      final restored = AppState(
        now: () => now,
        placesService: fixtures.FixedPlaces(),
      );
      await restored.bootstrap();
      expect(restored.current!.place.id, 'b');
      expect(restored.skippedThisMealCount, 1);
      await restored.setMood(Mood.adventure);
      expect(restored.current!.place.id, 'b');
      await restored.skipCurrentMeal();
      expect(restored.current, isNull);
      expect(restored.rerollsUsedToday, 2);
      now = DateTime(2026, 9, 18, 18);
      await restored.syncTime();
      expect(restored.skippedThisMealCount, 0);
      expect(restored.current, isNotNull);
      expect(restored.rerollsUsedToday, 2);
    },
  );

  test('restoring meal skips leaves permanent exclusions intact', () async {
    final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
    await app.excludeCurrentPlace();
    await app.skipCurrentMeal();
    expect(app.current, isNull);
    await app.restoreMealSkips();
    expect(app.current!.place.id, 'b');
    expect(app.prefs.excludedPlaceIds, {'a'});
  });

  test(
    'favorites toggle persists and does not confirm or change quota',
    () async {
      final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
      await app.toggleFavorite(fixtures.shopsFirst);
      expect((await StorageService().loadFavorites()).single.id, 'a');
      expect(app.history, isEmpty);
      expect(app.rerollsUsedToday, 0);
      await app.toggleFavorite(fixtures.shopsFirst);
      expect(await StorageService().loadFavorites(), isEmpty);
    },
  );

  test(
    'failed feedback, favorite and skip saves do not mutate visible state',
    () async {
      final app = fixtures.readyApp(
        () => DateTime(2026, 9, 18, 12),
        storage: FailingStorage(),
      );
      final entry = HistoryEntry(
        placeId: 'a',
        placeName: '甲店',
        confirmedAt: DateTime(2026, 9, 18, 12),
      );
      app.history = [entry];
      await expectLater(
        app.recordFeedback(entry.id, MealFeedback.liked),
        throwsStateError,
      );
      expect(app.history.single.feedback, MealFeedback.planned);
      await expectLater(
        app.toggleFavorite(fixtures.shopsFirst),
        throwsStateError,
      );
      expect(app.favorites, isEmpty);
      await expectLater(app.skipCurrentMeal(), throwsStateError);
      expect(app.skippedThisMealCount, 0);
      expect(app.current!.place.id, 'a');
      expect(app.isBusy, isFalse);
    },
  );

  test(
    'first launch does not request location or fetch; returning no-key Demo skips location',
    () async {
      final location = CountingLocation();
      final first = AppState(
        locationService: location,
        placesService: FailingPlaces(),
      );
      await first.bootstrap();
      expect(first.status, AppLoadStatus.ready);
      expect(location.calls, 0);
      expect(first.isDemo, isTrue);
      await first.skipColdStart();
      final returning = AppState(locationService: location);
      await returning.bootstrap();
      expect(returning.status, AppLoadStatus.ready);
      expect(returning.current, isNotNull);
      expect(location.calls, 0);
    },
  );

  test('failed refresh retains current card and offers recovery', () async {
    final app =
        AppState(
            locationService: CountingLocation(),
            placesService: FailingPlaces(),
          )
          ..status = AppLoadStatus.ready
          ..prefs = const UserPrefs(coldStartDone: true)
          ..nearby = fixtures.shops
          ..current = const Decision(
            place: fixtures.shopsFirst,
            reasonZh: '推薦',
            score: 1,
          );
    await app.refreshPlaces();
    expect(app.status, AppLoadStatus.ready);
    expect(app.current!.place.id, 'a');
    expect(app.actionError, isNotNull);
    expect(app.isBusy, isFalse);
  });
}
