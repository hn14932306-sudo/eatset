import 'dart:async';
import 'dart:convert';
import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/screens/history_screen.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/services/storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const real = Place(
  id: 'real_a',
  name: '旧店名',
  lat: 25,
  lng: 121,
  priceLevel: 2,
  rating: 4.8,
  userRatingsTotal: 300,
  vicinity: '舊地址',
  cuisineTags: ['重口味'],
);
const demo = Place(
  id: 'demo_a',
  name: '示範餐廳',
  lat: 25,
  lng: 121,
  isDemo: true,
  priceLevel: 1,
);

class RefreshService extends PlacesService {
  int calls = 0;
  bool fail = false;
  Completer<void>? gate;
  @override
  Future<Place> fetchDetails(String id) async {
    calls++;
    await gate?.future;
    if (fail) throw StateError('offline');
    return Place(
      id: id,
      name: '最新店名',
      lat: 25,
      lng: 121,
      priceLevel: 3,
      openNow: false,
      fetchedAt: DateTime.now(),
    );
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'legacy real snapshots are scrubbed while IDs, feedback, timestamps and Demo survive',
    () async {
      final at = DateTime(2026, 9, 19, 12);
      final old = HistoryEntry(
        placeId: real.id,
        placeName: real.name,
        confirmedAt: at,
        mealSlot: '午餐',
        feedback: MealFeedback.liked,
        place: real,
        cuisineTags: ['重口味'],
      );
      SharedPreferences.setMockInitialValues({
        'eatset_favorites': jsonEncode([real.toJson(), demo.toJson()]),
        'eatset_history': jsonEncode([old.toJson()]),
        'eatset_user_prefs': jsonEncode(
          UserPrefs(
            excludedPlaceIds: {real.id, demo.id},
            excludedPlaceNames: {real.id: real.name, demo.id: demo.name},
            excludedCategories: {'火鍋'},
          ).toJson(),
        ),
      });
      final storage = StorageService();
      final favorites = await storage.loadFavorites();
      final history = await storage.loadHistory();
      final prefs = await storage.loadPrefs();
      expect(favorites.first.isReference, isTrue);
      expect(favorites.first.priceLevel, isNull);
      expect(favorites.last.name, demo.name);
      expect(history.single.placeId, real.id);
      expect(history.single.confirmedAt, at);
      expect(history.single.feedback, MealFeedback.liked);
      expect(history.single.place, isNull);
      expect(history.single.cuisineTags, isEmpty);
      expect(prefs.excludedPlaceIds, {real.id, demo.id});
      expect(prefs.excludedCategories, {'火鍋'});
      final sp = await SharedPreferences.getInstance();
      for (final key in [
        'eatset_favorites',
        'eatset_history',
        'eatset_user_prefs',
      ]) {
        expect(sp.getString(key), isNot(contains(real.name)));
        expect(sp.getString(key), isNot(contains(real.vicinity!)));
      }
      expect(jsonDecode(sp.getString('eatset_history')!).single.keys.toSet(), {
        'placeId',
        'confirmedAt',
        'mealSlot',
        'feedback',
      });
    },
  );
  test(
    'new saves never persist Google content in real history or favorites',
    () async {
      final storage = StorageService();
      await storage.saveFavorites([real]);
      await storage.saveHistory([
        HistoryEntry(
          placeId: real.id,
          placeName: real.name,
          confirmedAt: DateTime.now(),
          place: real,
        ),
      ]);
      expect((await storage.loadFavorites()).single.needsRefresh, isTrue);
      expect((await storage.loadHistory()).single.place, isNull);
      final sp = await SharedPreferences.getInstance();
      expect(jsonDecode(sp.getString('eatset_favorites')!), [
        {'id': 'real_a', 'isDemo': false},
      ]);
    },
  );
  test(
    'details are deduplicated, refreshed in memory, and not written back to disk',
    () async {
      final service = RefreshService()..gate = Completer<void>();
      final app = AppState(placesService: service)
        ..favorites = [Place.reference(real.id)];
      final a = app.refreshPlace(real.id);
      final b = app.refreshPlace(real.id);
      expect(service.calls, 1);
      service.gate!.complete();
      await Future.wait([a, b]);
      expect(app.resolvePlace(real.id).name, '最新店名');
      expect(app.resolvePlace(real.id).priceLevel, 3);
      expect(app.resolvePlace(real.id).openNow, isFalse);
      await StorageService().saveFavorites([app.resolvePlace(real.id)]);
      expect(
        (await StorageService().loadFavorites()).single.isReference,
        isTrue,
      );
    },
  );
  test(
    'a stored ID without live data is never resolved as current and a failed update preserves favorites',
    () async {
      final service = RefreshService()..fail = true;
      final app = AppState(placesService: service)
        ..favorites = [Place.reference(real.id)];
      expect(app.resolvePlace(real.id).priceLevel, isNull);
      await expectLater(app.refreshPlace(real.id), throwsStateError);
      expect(app.favorites.single.id, real.id);
      expect(app.resolvePlace(real.id).openNow, isNull);
      expect(app.placeErrors[real.id], isNotNull);
      expect(app.isRefreshingPlace(real.id), isFalse);
    },
  );
  test('live place data has no clock expiry within a session', () {
    final hoursOld = Place(
      id: real.id,
      name: real.name,
      lat: 25,
      lng: 121,
      priceLevel: 2,
      openNow: true,
      fetchedAt: DateTime.now().subtract(const Duration(hours: 3)),
    );
    expect(hoursOld.needsRefresh, isFalse);
    final app = AppState(placesService: RefreshService())..nearby = [hoursOld];
    expect(app.resolvePlace(real.id).priceLevel, 2);
    expect(Place.reference(real.id).needsRefresh, isTrue);
  });
  test(
    'a choice without live data rechecks restrictions before storing a plan',
    () async {
      final app = AppState(placesService: RefreshService())
        ..status = AppLoadStatus.ready
        ..prefs = const UserPrefs(coldStartDone: true)
        ..current = Decision(
          place: Place.reference(real.id),
          reasonZh: '舊推薦',
          score: 1,
        );
      expect(await app.confirmCurrent(), isNull);
      expect(app.history, isEmpty);
      expect(app.actionError, contains('目前不符合'));
    },
  );
  test(
    'newer details override a recent recommendation before confirmation',
    () async {
      final service = RefreshService();
      final app = AppState(placesService: service)
        ..status = AppLoadStatus.ready
        ..prefs = const UserPrefs(coldStartDone: true)
        ..nearby = [real]
        ..current = const Decision(place: real, reasonZh: '推薦', score: 1);
      await app.refreshPlace(real.id, force: true);
      expect(await app.confirmCurrent(), isNull);
      expect(app.history, isEmpty);
      expect(app.actionError, contains('目前不符合'));
      service.fail = true;
      await expectLater(
        app.refreshPlace(real.id, force: true),
        throwsStateError,
      );
      expect(app.resolvePlace(real.id, fallback: real).isReference, isTrue);
    },
  );
  testWidgets(
    'saved history loads names only when active and offers retry without losing feedback',
    (tester) async {
      final service = RefreshService()..fail = true;
      final app = AppState(placesService: service)
        ..status = AppLoadStatus.ready
        ..history = [
          HistoryEntry(
            placeId: real.id,
            placeName: '店家資訊待更新',
            confirmedAt: DateTime.now(),
            feedback: MealFeedback.liked,
          ),
        ];
      Widget host(bool active) => ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(home: HistoryScreen(active: active)),
      );
      await tester.pumpWidget(host(false));
      await tester.pumpAndSettle();
      expect(service.calls, 0);
      await tester.pumpWidget(host(true));
      await tester.pumpAndSettle();
      expect(service.calls, 1);
      expect(find.text('店家資訊待更新'), findsOneWidget);
      expect(find.text('吃過，喜歡'), findsOneWidget);
      service.fail = false;
      await tester.tap(find.text('更新店家資訊'));
      await tester.pumpAndSettle();
      expect(find.text('最新店名'), findsOneWidget);
      expect(app.history.single.feedback, MealFeedback.liked);
      expect(tester.takeException(), isNull);
    },
  );
}
