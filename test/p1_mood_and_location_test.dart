import 'package:eatset/models/mood.dart';
import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/screens/home_screen.dart';
import 'package:eatset/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLocationService extends LocationService {
  LocationResult next = const LocationResult.failure(
    LocationFailureReason.denied,
  );
  int getCalls = 0;
  bool openedAppSettings = false;
  bool openedLocationSettings = false;

  @override
  Future<LocationResult> getCurrentLocation() async {
    getCalls += 1;
    return next;
  }

  @override
  Future<bool> openAppSettingsSafe() async {
    openedAppSettings = true;
    return true;
  }

  @override
  Future<bool> openLocationSettingsSafe() async {
    openedLocationSettings = true;
    return true;
  }
}

Place _place({
  required String id,
  required String name,
  List<String> tags = const ['麵'],
}) {
  return Place(
    id: id,
    name: name,
    lat: 25.0478,
    lng: 121.5170,
    rating: 4.5,
    userRatingsTotal: 100,
    distanceMeters: 100,
    isDemo: true,
    cuisineTags: tags,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('P1-5 mood toast / no reroll', () {
    test('setMood does not change rerollsUsedToday', () async {
      final a = _place(id: 'demo_a', name: '老王紅燒牛肉麵');
      final b = _place(id: 'demo_b', name: '阿美健康便當', tags: const ['飯']);

      final app = AppState();
      app.prefs = const UserPrefs(coldStartDone: true, mood: Mood.safe);
      app.nearby = [a, b];
      app.current = Decision(
        place: a,
        reasonZh: '評分不錯又夠近',
        score: 0.9,
        mealSlot: '午餐',
      );
      app.status = AppLoadStatus.ready;
      app.rerollsUsedToday = 2;

      final changed = await app.setMood(Mood.adventure);

      expect(changed, isTrue);
      expect(app.rerollsUsedToday, 2);
      expect(app.rerollsLeft, 1);
      expect(app.prefs.mood, Mood.adventure);
      expect(app.showMoodReselectedHint, isTrue);
    });

    test('setMood same mood is no-op without hint', () async {
      final app = AppState();
      app.prefs = const UserPrefs(coldStartDone: true, mood: Mood.any);
      app.nearby = [_place(id: 'demo_a', name: '店')];
      app.rerollsUsedToday = 1;

      final changed = await app.setMood(Mood.any);

      expect(changed, isFalse);
      expect(app.rerollsUsedToday, 1);
      expect(app.showMoodReselectedHint, isFalse);
    });

    test('consumeMoodReselectedHint clears flag', () async {
      final app = AppState();
      app.prefs = const UserPrefs(coldStartDone: true, mood: Mood.safe);
      app.nearby = [_place(id: 'demo_a', name: '店')];
      await app.setMood(Mood.any);
      expect(app.showMoodReselectedHint, isTrue);
      app.consumeMoodReselectedHint();
      expect(app.showMoodReselectedHint, isFalse);
    });

    testWidgets('mood chip change shows 「已依心情重新決定」 snackbar', (tester) async {
      final a = _place(id: 'demo_a', name: '老王紅燒牛肉麵');
      final b = _place(id: 'demo_b', name: '阿美健康便當', tags: const ['飯']);

      final app = AppState();
      app.prefs = const UserPrefs(coldStartDone: true, mood: Mood.safe);
      app.nearby = [a, b];
      app.current = Decision(
        place: a,
        reasonZh: '評分不錯又夠近',
        score: 0.9,
        mealSlot: '午餐',
      );
      app.status = AppLoadStatus.ready;
      app.isDemo = true;
      app.locationOk = true;
      app.rerollsUsedToday = 1;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to the secondary control below the restaurant card.
      await tester.scrollUntilVisible(
        find.text('微調心情'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('微調心情'));
      await tester.pumpAndSettle();

      expect(find.text('想試試新的'), findsOneWidget);
      await tester.ensureVisible(find.text('想試試新的'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('想試試新的'));
      await tester.pump(); // start async setMood
      await tester.pumpAndSettle();

      expect(find.text('已依心情重新決定'), findsOneWidget);
      expect(app.rerollsUsedToday, 1);
      expect(app.prefs.mood, Mood.adventure);
    });
  });

  group('P1-6 location deny help', () {
    test('LocationResult exposes deny states', () {
      const denied = LocationResult.failure(LocationFailureReason.denied);
      expect(denied.ok, isFalse);
      expect(denied.failure, LocationFailureReason.denied);

      const forever = LocationResult.failure(
        LocationFailureReason.deniedForever,
      );
      expect(forever.failure, LocationFailureReason.deniedForever);

      const off = LocationResult.failure(LocationFailureReason.serviceDisabled);
      expect(off.failure, LocationFailureReason.serviceDisabled);

      const ok = LocationResult.success(UserLocation(lat: 25.0, lng: 121.5));
      expect(ok.ok, isTrue);
      expect(ok.location!.lat, 25.0);
    });

    test('AppState tracks location deny flags from LocationService', () async {
      final fake = FakeLocationService()
        ..next = const LocationResult.failure(
          LocationFailureReason.deniedForever,
        );

      final app = AppState(locationService: fake);
      await app.refreshPlaces();

      expect(app.locationOk, isFalse);
      expect(app.locationDeniedForever, isTrue);
      expect(app.locationDenied, isFalse);
      expect(app.locationServiceDisabled, isFalse);
      expect(app.locationHelpSubtitle, contains('永久拒絕'));
    });

    test('enableLocation opens app settings when deniedForever', () async {
      final fake = FakeLocationService()
        ..next = const LocationResult.failure(
          LocationFailureReason.deniedForever,
        );

      final app = AppState(locationService: fake);
      await app.enableLocation();

      expect(fake.openedAppSettings, isTrue);
      expect(fake.openedLocationSettings, isFalse);
      expect(app.locationDeniedForever, isTrue);
      expect(app.locationOk, isFalse);
    });

    test(
      'enableLocation opens location settings when service disabled',
      () async {
        final fake = FakeLocationService()
          ..next = const LocationResult.failure(
            LocationFailureReason.serviceDisabled,
          );

        final app = AppState(locationService: fake);
        await app.enableLocation();

        expect(fake.openedLocationSettings, isTrue);
        expect(fake.openedAppSettings, isFalse);
        expect(app.locationServiceDisabled, isTrue);
        expect(app.locationHelpSubtitle, contains('定位服務已關閉'));
      },
    );

    testWidgets('banner shows locate CTA and deny copy when !locationOk', (
      tester,
    ) async {
      final app = AppState();
      app.prefs = const UserPrefs(coldStartDone: true);
      app.nearby = [_place(id: 'demo_a', name: '示範店')];
      app.current = Decision(
        place: app.nearby.first,
        reasonZh: '測試',
        score: 1,
        mealSlot: '午餐',
      );
      app.status = AppLoadStatus.ready;
      app.isDemo = true;
      app.locationOk = false;
      app.locationDenied = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('需要定位才能找附近餐廳'), findsOneWidget);
      expect(find.text('開啟定位'), findsOneWidget);
      expect(find.textContaining('尚未允許定位權限'), findsOneWidget);
    });

    testWidgets('banner shows forever-deny copy when flagged', (tester) async {
      final app = AppState();
      app.prefs = const UserPrefs(coldStartDone: true);
      app.nearby = [_place(id: 'demo_a', name: '示範店')];
      app.current = Decision(
        place: app.nearby.first,
        reasonZh: '測試',
        score: 1,
        mealSlot: '午餐',
      );
      app.status = AppLoadStatus.ready;
      app.isDemo = true;
      app.locationOk = false;
      app.locationDeniedForever = true;

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: const MaterialApp(home: HomeScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('永久拒絕'), findsOneWidget);
      expect(find.text('開啟定位'), findsOneWidget);
    });
  });
}
