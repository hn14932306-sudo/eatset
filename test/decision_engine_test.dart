import 'dart:math';

import 'package:eatset/models/meal_slot.dart';
import 'package:eatset/models/mood.dart';
import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DecisionEngine engine;

  setUp(() {
    engine = DecisionEngine(random: Random(42));
  });

  Place place({
    required String id,
    required String name,
    double rating = 4.5,
    int reviews = 100,
    double? distance = 300,
    List<String> tags = const [],
    bool open = true,
    bool demo = true,
    int? price = 1,
  }) {
    return Place(
      id: id,
      name: name,
      lat: 25.0,
      lng: 121.5,
      rating: rating,
      userRatingsTotal: reviews,
      distanceMeters: distance,
      cuisineTags: tags,
      openNow: open,
      isDemo: demo,
      priceLevel: price,
      types: const ['restaurant'],
    );
  }

  test('filters closed, far, excluded places', () {
    final prefs = UserPrefs(
      coldStartDone: true,
      excludedPlaceIds: {'bad'},
      excludedCategories: {'火鍋'},
    );
    final list = [
      place(id: 'ok', name: '好店', tags: ['麵']),
      place(id: 'closed', name: '休息中', open: false),
      place(id: 'far', name: '太遠', distance: 5000),
      place(id: 'bad', name: '已排除'),
      place(id: 'hotpot', name: '麻辣火鍋', tags: ['火鍋', '重口味']),
    ];
    final filtered = engine.filterCandidates(list, prefs);
    expect(filtered.map((p) => p.id), ['ok']);
  });

  test('prefers noodles when user chose 麵', () {
    final prefs = const UserPrefs(
      prefersNoodles: true,
      mood: Mood.safe,
      coldStartDone: true,
    );
    final noodle = place(id: 'n', name: '牛肉麵', tags: ['麵', '重口味'], rating: 4.4);
    final rice = place(id: 'r', name: '雞腿飯', tags: ['飯'], rating: 4.4);
    final sn = engine.scorePlace(noodle, prefs, mealSlot: MealSlot.lunch);
    final sr = engine.scorePlace(rice, prefs, mealSlot: MealSlot.lunch);
    expect(sn, greaterThan(sr));
  });

  test('decide returns one place with zh reason', () {
    final prefs = const UserPrefs(
      prefersNoodles: true,
      prefersLight: false,
      mood: Mood.safe,
      coldStartDone: true,
    );
    final places = [
      place(id: 'a', name: '老王牛肉麵', tags: ['麵', '重口味'], rating: 4.6),
      place(id: 'b', name: '清粥小菜', tags: ['飯', '清淡'], rating: 4.2),
    ];
    final d = engine.decide(places, prefs, mealSlot: MealSlot.dinner);
    expect(d, isNotNull);
    expect(d!.place.id, 'a');
    expect(d.reasonZh, isNotEmpty);
    expect(d.reasonZh.contains('晚餐') || d.reasonZh.contains('麵'), isTrue);
  });

  test('balance nudge triggers after heavy week', () {
    final now = DateTime(2026, 9, 17, 12);
    final history = List.generate(
      4,
      (i) => HistoryEntry(
        placeId: 'h$i',
        placeName: '麻辣火鍋$i',
        confirmedAt: now.subtract(Duration(days: i + 1)),
        cuisineTags: const ['重口味', '火鍋'],
        feedback: MealFeedback.neutral,
      ),
    );
    expect(
      engine.shouldOfferBalanceNudge(
        history: history,
        now: now,
        lastBalanceNudgeAt: null,
      ),
      isTrue,
    );
    expect(
      engine.shouldOfferBalanceNudge(
        history: history,
        now: now,
        lastBalanceNudgeAt: now.subtract(const Duration(days: 2)),
      ),
      isFalse,
    );
  });

  test('MealSlot windows are Taiwan-friendly', () {
    expect(MealSlot.fromDateTime(DateTime(2026, 1, 1, 8)), MealSlot.breakfast);
    expect(MealSlot.fromDateTime(DateTime(2026, 1, 1, 12)), MealSlot.lunch);
    expect(MealSlot.fromDateTime(DateTime(2026, 1, 1, 18)), MealSlot.dinner);
    expect(MealSlot.fromDateTime(DateTime(2026, 1, 1, 23)), MealSlot.lateNight);
    expect(MealSlot.fromDateTime(DateTime(2026, 1, 1, 3)), MealSlot.lateNight);
  });
}
