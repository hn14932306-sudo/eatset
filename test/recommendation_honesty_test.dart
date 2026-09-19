import 'dart:convert';

import 'package:eatset/models/meal_slot.dart';
import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/widgets/decision_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Place restaurant(
  String name, {
  List<String> tags = const [],
  bool demo = false,
  double rating = 4.5,
}) => Place(
  id: name,
  name: name,
  lat: 25,
  lng: 121,
  rating: rating,
  userRatingsTotal: 100,
  distanceMeters: 100,
  cuisineTags: tags,
  isDemo: demo,
  priceLevel: 1,
);

class TestLocation extends LocationService {
  TestLocation(this.result);
  final LocationResult result;
  @override
  Future<LocationResult> getCurrentLocation() async => result;
}

class TestPlaces extends PlacesService {
  TestPlaces({this.demo = false});
  final bool demo;
  @override
  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = PlacesService.defaultRadiusMeters,
  }) async => PlacesResult(
    places: [restaurant('測試店', demo: demo)],
    isDemo: demo,
    usedDeviceLocation: location?.fromDevice == true,
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'balance request without light evidence falls back without false claims',
    () {
      final engine = DecisionEngine();
      final decision = engine.decide(
        [
          restaurant('燒肉店', tags: ['重口味']),
          restaurant('麻辣蔬食', tags: ['清淡', '重口味']),
          restaurant('一般餐廳'),
        ],
        const UserPrefs(),
        mealSlot: MealSlot.lunch,
        forceBalance: true,
      )!;
      expect(decision.isBalanceNudge, isFalse);
      expect(decision.reasonZh, isNot(contains('清爽')));
      expect(decision.reasonZh, isNot(contains('均衡')));
    },
  );

  test(
    'balance picks evidence-backed option despite a higher-rated heavy option',
    () {
      final decision = DecisionEngine().decide(
        [
          restaurant('高評價燒肉', tags: ['重口味'], rating: 5),
          restaurant('清淡小店', tags: ['清淡'], rating: 3.6),
        ],
        const UserPrefs(),
        mealSlot: MealSlot.lunch,
        forceBalance: true,
      )!;
      expect(decision.place.name, '清淡小店');
      expect(decision.isBalanceNudge, isTrue);
      expect(decision.reasonZh, contains('確認菜單'));
      expect(decision.reasonZh, isNot(contains('評價不錯')));
    },
  );

  test(
    'reason only uses straight-line distance with a real location and real shop',
    () {
      final engine = DecisionEngine();
      final shop = restaurant('測試店');
      final hidden = engine.buildReason(
        shop,
        const UserPrefs(),
        mealSlot: MealSlot.lunch,
      );
      expect(hidden, isNot(contains('公尺')));
      final shown = engine.buildReason(
        shop,
        const UserPrefs(),
        mealSlot: MealSlot.lunch,
        showRealDistance: true,
      );
      expect(shown, contains('直線距離約 100 公尺'));
      expect(shown, isNot(contains('走路')));
      final demo = engine.buildReason(
        restaurant('示範', demo: true),
        const UserPrefs(),
        mealSlot: MealSlot.lunch,
        showRealDistance: true,
      );
      expect(demo, isNot(contains('公尺')));
    },
  );

  testWidgets(
    'debug fallback never leaks anchor distance into card or reason',
    (tester) async {
      final app = AppState(
        locationService: TestLocation(
          const LocationResult.success(LocationService.debugFallbackLocation),
        ),
        placesService: TestPlaces(),
      );
      app.prefs = const UserPrefs(coldStartDone: true);
      await app.refreshPlaces();
      expect(app.locationOk, isFalse);
      expect(app.showRealDistance, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DecisionCard(
              decision: app.current!,
              showRealDistance: app.showRealDistance,
            ),
          ),
        ),
      );
      expect(find.textContaining('公尺'), findsNothing);
      expect(find.textContaining('公里'), findsNothing);
      expect(find.textContaining('走路'), findsNothing);
    },
  );

  test('real location with Demo still hides fabricated distances', () async {
    final app = AppState(
      locationService: TestLocation(
        const LocationResult.success(UserLocation(lat: 25, lng: 121)),
      ),
      placesService: TestPlaces(demo: true),
    );
    app.prefs = const UserPrefs(coldStartDone: true);
    await app.refreshPlaces();
    expect(app.locationOk, isTrue);
    expect(app.showRealDistance, isFalse);
    expect(app.current!.reasonZh, isNot(contains('公尺')));
  });

  test(
    'Places omits anchor-relative distance, retaining real device distances',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'places': [
              {
                'id': 'real',
                'displayName': {'text': '真店'},
                'location': {'latitude': 25.048, 'longitude': 121.517},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      final service = PlacesService(
        client: client,
        baseUrl: 'https://api.example',
      );
      final fallback = await service.fetchNearby(
        location: LocationService.debugFallbackLocation,
      );
      expect(fallback.isDemo, isTrue);
      final missing = await service.fetchNearby();
      expect(missing.isDemo, isTrue);
      final located = await service.fetchNearby(
        location: const UserLocation(lat: 25.0478, lng: 121.517),
      );
      expect(located.places.single.distanceMeters, isNotNull);
    },
  );
}
