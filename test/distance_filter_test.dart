import 'package:eatset/models/place.dart';
import 'package:eatset/models/search_range.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/screens/home_screen.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Place shop(String id, double meters) => Place(
  id: id,
  name: '店$id',
  lat: 25,
  lng: 121,
  rating: 4.5,
  userRatingsTotal: 100,
  priceLevel: 1,
  distanceMeters: meters,
  openNow: true,
  fetchedAt: DateTime.now(),
);

class Here extends LocationService {
  @override
  Future<LocationResult> getCurrentLocation() async =>
      const LocationResult.success(UserLocation(lat: 25, lng: 121));
}

/// Serves whatever is within the requested radius and records each request.
class RadiusPlaces extends PlacesService {
  final radii = <int>[];
  final all = [
    shop('a', 200),
    shop('b', 350),
    shop('c', 450),
    shop('d', 700),
    shop('e', 1100),
    shop('f', 1900),
  ];
  @override
  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = PlacesService.defaultRadiusMeters,
  }) async {
    radii.add(radiusMeters);
    return PlacesResult(
      places: all.where((p) => p.distanceMeters! <= radiusMeters).toList(),
      isDemo: false,
      usedDeviceLocation: true,
    );
  }
}

AppState app(RadiusPlaces places, {int radius = 1200}) {
  final list = places.all.where((p) => p.distanceMeters! <= radius).toList();
  return AppState(placesService: places, locationService: Here())
    ..status = AppLoadStatus.ready
    ..prefs = UserPrefs(coldStartDone: true, maxDistanceMeters: radius)
    ..isDemo = false
    ..locationOk = true
    ..nearby = list
    ..nearbyFetchedAt = DateTime.now()
    ..nearbyRadius = radius
    ..nearbyCenter = const UserLocation(lat: 25, lng: 121)
    ..current = Decision(place: list.first, reasonZh: '推薦', score: 1);
}

Future<void> apply(AppState state, int meters) => state.setDiningFilters(
  budget: state.prefs.mealBudget,
  includeHotels: state.prefs.includeHotelRestaurants,
  includeUnknownPrices: state.prefs.includeUnknownPrices,
  maxDistanceMeters: meters,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('range values', () {
    test('labels read naturally', () {
      expect(SearchRange.label(500), '500 公尺');
      expect(SearchRange.label(1200), '1.2 公里');
      expect(SearchRange.label(2000), '2 公里');
    });

    test(
      'unknown values fall back to the default and never reach the backend',
      () {
        expect(SearchRange.normalize(800), 800);
        expect(SearchRange.normalize(5000), SearchRange.defaultMeters);
        expect(SearchRange.normalize(null), SearchRange.defaultMeters);
        expect(SearchRange.normalize('800'), SearchRange.defaultMeters);
      },
    );

    test('saved preferences keep the range; older ones get the default', () {
      final saved = UserPrefs.fromJson(
        const UserPrefs(maxDistanceMeters: 800).toJson(),
      );
      expect(saved.maxDistanceMeters, 800);
      expect(UserPrefs.fromJson(const {}).maxDistanceMeters, 1200);
      expect(
        UserPrefs.fromJson(const {'maxDistanceMeters': 99}).maxDistanceMeters,
        1200,
      );
      expect(
        const UserPrefs().copyWith(maxDistanceMeters: 31337).maxDistanceMeters,
        1200,
      );
    });
  });

  group('engine', () {
    test(
      'only places within the chosen straight-line range are candidates',
      () {
        final places = [shop('a', 300), shop('b', 900), shop('c', 1500)];
        ids(int m) => DecisionEngine()
            .filterCandidates(places, UserPrefs(maxDistanceMeters: m))
            .map((p) => p.id)
            .toList();
        expect(ids(500), ['a']);
        expect(ids(1200), ['a', 'b']);
        expect(ids(2000), ['a', 'b', 'c']);
      },
    );

    test('a place with no known distance is not filtered out', () {
      const unknown = Place(
        id: 'x',
        name: 'x',
        lat: 25,
        lng: 121,
        rating: 4.5,
        userRatingsTotal: 100,
        priceLevel: 1,
      );
      expect(
        DecisionEngine().filterCandidates([
          unknown,
        ], const UserPrefs(maxDistanceMeters: 500)),
        hasLength(1),
      );
    });
  });

  group('search cost', () {
    test('widening the range searches once at the new radius', () async {
      final places = RadiusPlaces();
      final state = app(places, radius: 800);
      await apply(state, 2000);
      expect(places.radii, [2000]);
      expect(state.nearby.map((p) => p.id), contains('f'));
      expect(state.nearbyRadius, 2000);
      expect(state.prefs.maxDistanceMeters, 2000);
    });

    test(
      'narrowing with plenty left is a local filter and costs nothing',
      () async {
        final places = RadiusPlaces();
        final state = app(places, radius: 2000);
        await apply(state, 800); // a, b, c, d remain
        expect(places.radii, isEmpty);
        expect(state.current!.place.distanceMeters, lessThanOrEqualTo(800));
        expect(
          state.alternatives.every((p) => p.distanceMeters! <= 800),
          isTrue,
        );
      },
    );

    test(
      'narrowing that leaves enough candidates stays local, even if repeated',
      () async {
        final places = RadiusPlaces();
        final state = app(places, radius: 2000);
        await apply(state, 500); // a, b, c remain: enough to choose from
        await apply(state, 500); // unchanged range: nothing to do
        expect(places.radii, isEmpty);
      },
    );

    test(
      'narrowing that leaves too few candidates searches once at the smaller radius',
      () async {
        final places = RadiusPlaces()..all.removeWhere((p) => p.id == 'c');
        final state = app(places, radius: 2000);
        await apply(state, 500); // only a, b remain
        expect(places.radii, [500]);
        expect(state.nearbyRadius, 500);
      },
    );

    test('a changed filter other than range never searches', () async {
      final places = RadiusPlaces();
      final state = app(places);
      await state.setDiningFilters(
        budget: state.prefs.mealBudget,
        includeHotels: true,
        includeUnknownPrices: false,
      );
      expect(places.radii, isEmpty);
      expect(state.prefs.maxDistanceMeters, 1200);
    });

    test('demo results are never searched for', () async {
      final places = RadiusPlaces();
      final state = app(places)..isDemo = true;
      await apply(state, 2000);
      expect(places.radii, isEmpty);
    });

    test('the range is saved and used by the next ordinary search', () async {
      final places = RadiusPlaces();
      final state = app(places, radius: 800);
      await apply(state, 500);
      expect((await StorageService().loadPrefs()).maxDistanceMeters, 500);
      state.nearbyFetchedAt = DateTime.now().subtract(
        const Duration(minutes: 5),
      );
      await state.refreshPlaces();
      expect(places.radii.last, 500);
    });
  });

  testWidgets(
    'the filter sheet offers ranges, shows a non-default one on the chip, and saves it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final places = RadiusPlaces();
      final state = app(places);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.tap(find.text('價格：日常'));
      await tester.pumpAndSettle();
      for (final m in SearchRange.options) {
        expect(find.byKey(Key('range_$m')), findsOneWidget);
      }
      expect(find.textContaining('直線距離計算'), findsOneWidget);
      await tester.tap(find.byKey(const Key('range_500')));
      await tester.tap(find.text('套用並重新推薦'));
      await tester.pumpAndSettle();
      expect(state.prefs.maxDistanceMeters, 500);
      expect(find.text('價格：日常 · 500 公尺'), findsOneWidget);
      expect((await StorageService().loadPrefs()).maxDistanceMeters, 500);
    },
  );
}
