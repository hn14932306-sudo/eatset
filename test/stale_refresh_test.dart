import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FixedLocation extends LocationService {
  bool ok = true;
  double lat = 25;
  @override
  Future<LocationResult> getCurrentLocation() async => ok
      ? LocationResult.success(UserLocation(lat: lat, lng: 121))
      : const LocationResult.failure(LocationFailureReason.error);
}

Place shop(String id, {DateTime? at}) => Place(
  id: id,
  name: '店$id',
  lat: 25,
  lng: 121,
  rating: 4.5,
  userRatingsTotal: 100,
  priceLevel: 1,
  distanceMeters: 250,
  openNow: true,
  fetchedAt: at ?? DateTime.now(),
);

class CountingPlaces extends PlacesService {
  int searches = 0;
  bool fail = false;
  bool demo = false;
  @override
  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = PlacesService.defaultRadiusMeters,
  }) async {
    searches++;
    if (fail) throw StateError('offline');
    return PlacesResult(
      places: demo ? const [] : [shop('a'), shop('b'), shop('c')],
      isDemo: demo,
      usedDeviceLocation: true,
    );
  }
}

/// Real results searched at [fetched] (25,121), the clock at [now], `a` shown.
AppState app(
  CountingPlaces places,
  FixedLocation location, {
  required DateTime fetched,
  required DateTime now,
}) {
  final list = [
    shop('a', at: fetched),
    shop('b', at: fetched),
    shop('c', at: fetched),
  ];
  return AppState(
      placesService: places,
      locationService: location,
      now: () => now,
    )
    ..status = AppLoadStatus.ready
    ..prefs = const UserPrefs(coldStartDone: true)
    ..isDemo = false
    ..locationOk = true
    ..nearby = list
    ..nearbyFetchedAt = fetched
    ..nearbyCenter = const UserLocation(lat: 25, lng: 121)
    ..current = Decision(place: list.first, reasonZh: '推薦', score: 1);
}

void main() {
  late CountingPlaces places;
  late FixedLocation location;
  // Lunch is 10:30-14:29, dinner 14:30-20:29.
  final lunchEarly = DateTime(2026, 9, 19, 11, 0);
  final lunchLate = DateTime(2026, 9, 19, 14, 0);
  final dinner = DateTime(2026, 9, 19, 18, 0);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    places = CountingPlaces();
    location = FixedLocation();
  });

  test(
    'data never expires by the clock: hours later in the same meal costs nothing',
    () async {
      final state = app(places, location, fetched: lunchEarly, now: lunchLate);
      expect(state.nearbyIsOutdated, isFalse);
      await state.refreshIfOutdated();
      await state.reroll();
      expect(places.searches, 0);
      expect(state.current, isNotNull);
      expect(state.alternatives, isNotEmpty);
    },
  );

  test(
    'a list searched in an earlier meal is re-searched once and the shown restaurant stays',
    () async {
      final state = app(places, location, fetched: lunchEarly, now: dinner);
      expect(state.nearbyIsOutdated, isTrue);
      await state.refreshIfOutdated();
      expect(places.searches, 1);
      expect(state.current!.place.id, 'a');
      expect(state.nearbyIsOutdated, isFalse);
      await state.refreshIfOutdated();
      expect(places.searches, 1);
    },
  );

  test('a list from yesterday is outdated even in the same meal slot', () {
    final state = app(
      places,
      location,
      fetched: DateTime(2026, 9, 18, 12),
      now: DateTime(2026, 9, 19, 12),
    );
    expect(state.nearbyIsOutdated, isTrue);
  });

  test(
    'reroll and picking an alternative refresh an outdated list first',
    () async {
      final rerolled = app(places, location, fetched: lunchEarly, now: dinner);
      await rerolled.reroll();
      expect(places.searches, 1);
      expect(rerolled.current!.place.id, isNot('a'));

      final picked = app(places, location, fetched: lunchEarly, now: dinner);
      expect(await picked.selectAlternative('b'), isTrue);
      expect(places.searches, 2);
      expect(picked.current!.place.id, 'b');
    },
  );

  test(
    'coming back somewhere else re-searches; staying put does not',
    () async {
      final state = app(places, location, fetched: lunchEarly, now: lunchLate);
      await state.refreshIfOutdated(checkMoved: true);
      expect(places.searches, 0, reason: 'same spot');
      location.lat = 25.02; // about 2.2 km north
      await state.refreshIfOutdated(checkMoved: true);
      expect(places.searches, 1);
      expect(state.nearbyCenter!.lat, 25.02);
    },
  );

  test('a failed refresh keeps the old real results', () async {
    final state = app(places, location, fetched: lunchEarly, now: dinner);
    places.fail = true;
    await state.refreshIfOutdated();
    expect(state.isDemo, isFalse);
    expect(state.nearby, hasLength(3));
    expect(state.current!.place.id, 'a');
    expect(state.status, AppLoadStatus.ready);
    expect(state.actionError, isNotNull);
  });

  test('never trades real places for demo or empty results', () async {
    final state = app(places, location, fetched: lunchEarly, now: dinner);
    places.demo = true;
    await state.refreshIfOutdated();
    expect(state.isDemo, isFalse);
    expect(state.nearby.first.id, 'a');
    location.ok = false;
    places.demo = false;
    await state.refreshIfOutdated();
    expect(places.searches, 1, reason: 'no location, so no search at all');
    expect(state.isDemo, isFalse);
  });

  test(
    'pull-to-refresh within 90 seconds does not pay for a repeat search',
    () async {
      final state = app(
        places,
        location,
        fetched: DateTime.now().subtract(const Duration(seconds: 20)),
        now: DateTime.now(),
      );
      await state.refreshPlacesUnlessRecent();
      expect(places.searches, 0);
      state.nearbyFetchedAt = DateTime.now().subtract(
        const Duration(seconds: 100),
      );
      await state.refreshPlacesUnlessRecent();
      expect(places.searches, 1);
    },
  );

  test(
    'an explicit retry is never throttled when there is nothing to show',
    () async {
      final state = AppState(placesService: places, locationService: location)
        ..status = AppLoadStatus.ready
        ..prefs = const UserPrefs(coldStartDone: true);
      await state.refreshPlacesUnlessRecent();
      expect(places.searches, 1);
    },
  );
}
