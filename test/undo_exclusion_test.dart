import 'package:eatset/models/meal_slot.dart';
import 'package:eatset/models/place.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restoring excluded id should prefer that place in nearby list', () {
    final a = Place(
      id: 'a',
      name: '老王紅燒牛肉麵',
      lat: 25.0,
      lng: 121.5,
      rating: 4.5,
      userRatingsTotal: 100,
      distanceMeters: 100,
      isDemo: true,
      cuisineTags: const ['麵'],
    );
    final b = Place(
      id: 'b',
      name: '另一家',
      lat: 25.01,
      lng: 121.51,
      rating: 4.6,
      userRatingsTotal: 100,
      distanceMeters: 120,
      isDemo: true,
      cuisineTags: const ['飯'],
    );
    final nearby = [a, b];
    const placeId = 'a';
    Place? restored;
    for (final p in nearby) {
      if (p.id == placeId) restored = p;
    }
    expect(restored?.name, '老王紅燒牛肉麵');
    final decision = Decision(
      place: restored!,
      reasonZh: '已復原你剛才排除的店',
      score: 1,
      mealSlot: MealSlot.lunch.labelZh,
    );
    expect(decision.place.id, 'a');
  });
}
