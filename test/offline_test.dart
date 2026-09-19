import 'dart:convert';

import 'package:eatset/models/place.dart';
import 'package:eatset/models/place_photo.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/screens/home_screen.dart';
import 'package:eatset/screens/place_details_sheet.dart';
import 'package:eatset/services/backend_client.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/photo_memory_cache.dart';
import 'package:eatset/services/place_photos_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/widgets/place_photo_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  vicinity: '台北市$id路',
  openNow: true,
  fetchedAt: DateTime.now(),
);

class Here extends LocationService {
  @override
  Future<LocationResult> getCurrentLocation() async =>
      const LocationResult.success(UserLocation(lat: 25, lng: 121));
}

/// A connection that can be cut at any time.
class Flaky extends PlacesService {
  bool online = true;
  int searches = 0;
  @override
  bool get isConfigured => true;
  @override
  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = PlacesService.defaultRadiusMeters,
  }) async {
    searches++;
    if (!online) throw const BackendException('NETWORK_FAILED');
    return PlacesResult(
      places: [shop('n1', 100), shop('n2', 200), shop('n3', 300)],
      isDemo: false,
      usedDeviceLocation: true,
    );
  }

  @override
  Future<Place> fetchDetails(String id) async {
    if (!online) throw const BackendException('NETWORK_FAILED');
    return shop(id, 100);
  }
}

AppState loaded(Flaky places, {DateTime? at, DateTime? now}) {
  final list = [shop('a', 100), shop('b', 200), shop('c', 300), shop('d', 400)];
  return AppState(
      placesService: places,
      locationService: Here(),
      now: now == null ? null : () => now,
    )
    ..status = AppLoadStatus.ready
    ..prefs = const UserPrefs(coldStartDone: true)
    ..isDemo = false
    ..locationOk = true
    ..nearby = list
    ..nearbyFetchedAt = at ?? DateTime.now()
    ..nearbyRadius = 1200
    ..nearbyCenter = const UserLocation(lat: 25, lng: 121)
    ..current = Decision(place: list.first, reasonZh: '推薦', score: 1);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PhotoMemoryCache.shared.clear();
  });

  group('results already on screen with the connection cut', () {
    test('choosing, filtering and confirming all still work', () async {
      final places = Flaky()..online = false;
      final state = loaded(places);

      await state.reroll();
      expect(state.current, isNotNull);
      expect(state.current!.place.id, isNot('a'));

      final alt = state.alternatives.first;
      expect(await state.selectAlternative(alt.id), isTrue);
      expect(state.current!.place.id, alt.id);

      await state.setDiningFilters(
        budget: state.prefs.mealBudget,
        includeHotels: state.prefs.includeHotelRestaurants,
        includeUnknownPrices: state.prefs.includeUnknownPrices,
        maxDistanceMeters: 500,
      );
      expect(state.prefs.maxDistanceMeters, 500);
      expect(state.current!.place.distanceMeters, lessThanOrEqualTo(500));

      final confirmed = await state.confirmCurrent();
      expect(confirmed, isNotNull);
      expect(state.history.single.placeId, confirmed!.id);
      expect(places.searches, 0, reason: 'nothing here needs the network');
    });

    test(
      'a failed pull-to-refresh keeps every result and explains why',
      () async {
        final places = Flaky()..online = false;
        final state = loaded(
          places,
          at: DateTime.now().subtract(const Duration(minutes: 10)),
        );
        await state.refreshPlacesUnlessRecent();
        expect(places.searches, 1);
        expect(state.nearby.map((p) => p.id), ['a', 'b', 'c', 'd']);
        expect(state.current!.place.id, 'a');
        expect(state.status, AppLoadStatus.ready);
        expect(state.offline, isTrue);
        expect(state.actionError, isNull, reason: 'the banner says it');

        places.online = true;
        await state.refreshPlaces();
        expect(state.offline, isFalse);
        expect(state.nearby.map((p) => p.id), ['n1', 'n2', 'n3']);
      },
    );

    test(
      'coming back in a later meal without a connection still shows the list',
      () async {
        final places = Flaky()..online = false;
        final state = loaded(
          places,
          at: DateTime(2026, 9, 19, 11),
          now: DateTime(2026, 9, 19, 18),
        );
        expect(state.nearbyIsOutdated, isTrue);
        await state.refreshIfOutdated();
        expect(state.offline, isTrue);
        expect(state.nearby, hasLength(4));
        expect(state.current!.place.id, 'a');
        expect(state.actionError, isNull);
      },
    );

    test(
      'widening the range offline saves the choice and keeps the old list',
      () async {
        final places = Flaky()..online = false;
        final state = loaded(places);
        await state.setDiningFilters(
          budget: state.prefs.mealBudget,
          includeHotels: false,
          includeUnknownPrices: true,
          maxDistanceMeters: 2000,
        );
        expect(state.prefs.maxDistanceMeters, 2000);
        expect(state.offline, isTrue);
        expect(state.nearby, hasLength(4));
        expect(state.current, isNotNull);
      },
    );

    test(
      'a cold start with no connection says so, and can be retried',
      () async {
        SharedPreferences.setMockInitialValues({
          'eatset_user_prefs': jsonEncode(
            const UserPrefs(coldStartDone: true).toJson(),
          ),
        });
        final places = Flaky()..online = false;
        final state = AppState(placesService: places, locationService: Here());
        await state.bootstrap();
        expect(state.status, AppLoadStatus.error);
        expect(state.offline, isTrue);
        expect(state.errorMessage, contains('網路'));
        places.online = true;
        await state.bootstrap();
        expect(state.status, AppLoadStatus.ready);
        expect(state.offline, isFalse);
      },
    );

    test('the plain network error reads as a connection problem', () {
      expect(const BackendException('NETWORK_FAILED').message, contains('網路'));
    });
  });

  group('coming back to the app', () {
    test('a dropped connection is retried once when the app returns', () async {
      final places = Flaky()..online = false;
      final state = loaded(
        places,
        at: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      await state.refreshPlacesUnlessRecent();
      expect(state.offline, isTrue);
      final before = places.searches;

      await state.retryAfterOffline(); // still down: one attempt, all kept
      expect(places.searches, before + 1);
      expect(state.offline, isTrue);
      expect(state.nearby.map((p) => p.id), ['a', 'b', 'c', 'd']);
      expect(state.actionError, isNull);

      places.online = true;
      await state.retryAfterOffline();
      expect(state.offline, isFalse);
      expect(state.nearby.map((p) => p.id), ['n1', 'n2', 'n3']);
      expect(state.current, isNotNull);

      final after = places.searches;
      await state.retryAfterOffline(); // back online: nothing more to do
      expect(places.searches, after);
    });

    test('nothing is retried when the connection was never lost', () async {
      final places = Flaky();
      final state = loaded(places);
      await state.retryAfterOffline();
      expect(places.searches, 0);
    });

    test(
      'a cold start that failed for lack of a connection recovers',
      () async {
        SharedPreferences.setMockInitialValues({
          'eatset_user_prefs': jsonEncode(
            const UserPrefs(coldStartDone: true).toJson(),
          ),
        });
        final places = Flaky()..online = false;
        final state = AppState(placesService: places, locationService: Here());
        await state.bootstrap();
        expect(state.status, AppLoadStatus.error);
        places.online = true;
        await state.retryAfterOffline();
        expect(state.status, AppLoadStatus.ready);
        expect(state.nearby, isNotEmpty);
        expect(state.offline, isFalse);
      },
    );

    test(
      'an already decided meal does not spend a search on returning',
      () async {
        final noon = DateTime(2026, 9, 19, 12);
        final places = Flaky()..online = false;
        final state = loaded(places, at: noon, now: noon)
          ..history = [
            HistoryEntry(
              placeId: 'a',
              placeName: '店a',
              confirmedAt: noon,
              mealSlot: '午餐',
            ),
          ]
          ..offline = true;
        expect(state.hasConfirmedMeal, isTrue);
        await state.retryAfterOffline();
        expect(places.searches, 0);
      },
    );
  });

  group('screens', () {
    testWidgets(
      'home keeps the card and alternatives and shows an offline banner',
      (tester) async {
        tester.view.physicalSize = const Size(390, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final places = Flaky()..online = false;
        final state = loaded(
          places,
          at: DateTime.now().subtract(const Duration(minutes: 10)),
        );
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: state,
            child: const MaterialApp(home: HomeScreen()),
          ),
        );
        expect(find.byKey(const Key('offline_banner')), findsNothing);
        await state.refreshPlacesUnlessRecent();
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('offline_banner')), findsOneWidget);
        expect(find.text('目前沒有網路連線'), findsOneWidget);
        expect(find.text('店a'), findsOneWidget);
        expect(find.byKey(const ValueKey('alternative-b')), findsOneWidget);
        expect(find.text('就吃這家'), findsOneWidget);

        places.online = true;
        await tester.tap(find.text('重新連線'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('offline_banner')), findsNothing);
      },
    );

    testWidgets(
      'details of a loaded restaurant open with no network and no error text',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: PlaceDetailsSheet(place: shop('a', 100))),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('店a'), findsOneWidget);
        expect(find.text('台北市a路'), findsOneWidget);
        expect(find.textContaining('暫時無法取得'), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      },
    );
  });

  group('photos', () {
    final pixel = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGPYXu7yHwAFzQJyQRqgsAAAAABJRU5ErkJggg==',
    );
    Place twoPhotos() => Place(
      id: 'a',
      name: '甲店',
      lat: 25,
      lng: 121,
      photos: [
        for (final n in ['one', 'two'])
          PlacePhoto.fromGoogle({
            'name': 'places/a/photos/$n',
            'token': 'token-$n',
          }, 'a')!,
      ],
      photosExpiresAt: DateTime.now().add(const Duration(minutes: 20)),
    );

    testWidgets(
      'a photo already seen still shows offline; an unseen one explains, and going back works',
      (tester) async {
        var online = true;
        final service = PlacePhotosService(
          baseUrl: 'https://api.example',
          client: MockClient((r) async {
            if (!online) throw http.ClientException('offline');
            return http.Response.bytes(
              pixel,
              200,
              headers: {'content-type': 'image/png'},
            );
          }),
        );
        addTearDown(service.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: PlacePhotoGallery(
                  place: twoPhotos(),
                  service: service,
                  autoLoadDelay: Duration.zero,
                ),
              ),
            ),
          ),
        );
        Future<void> settle() async {
          await tester.pumpAndSettle();
          await tester.runAsync(
            () async => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
        }

        await settle();
        expect(find.byType(Image), findsOneWidget);

        online = false;
        await tester.tap(find.byTooltip('下一張照片'));
        await settle();
        expect(find.textContaining('沒有網路'), findsOneWidget);
        expect(find.byType(Image), findsNothing);

        await tester.tap(find.byTooltip('上一張照片'));
        await settle();
        expect(
          find.byType(Image),
          findsOneWidget,
          reason: 'served from memory',
        );
        expect(find.textContaining('沒有網路'), findsNothing);
      },
    );
  });
}
