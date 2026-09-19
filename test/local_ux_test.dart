import 'package:eatset/providers/app_state.dart';
import 'package:eatset/screens/app_shell.dart';
import 'package:eatset/screens/cold_start_screen.dart';
import 'package:eatset/screens/confirm_screen.dart';
import 'package:eatset/screens/place_details_sheet.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/widgets/decision_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'meal_lifecycle_test.dart' as fixtures;

Widget host(AppState app, Widget child, {double scale = 1}) =>
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: child,
      ),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'phone navigation supports preview, favorite and feedback without accidental confirmation',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
      await tester.pumpWidget(host(app, const AppShell()));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('就吃這家'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('就吃這家').hitTestable(), findsOneWidget);
      await tester.tap(find.text('詳情'));
      await tester.pumpAndSettle();
      expect(find.text('在 Google Maps 查看'), findsOneWidget);
      expect(app.history, isEmpty);
      Navigator.of(tester.element(find.text('在 Google Maps 查看'))).pop();
      await tester.pumpAndSettle();
      final favorite = find.descendant(
        of: find.byType(DecisionCard),
        matching: find.byTooltip('收藏'),
      );
      await tester.ensureVisible(favorite);
      await tester.pumpAndSettle();
      await tester.tap(favorite);
      await tester.pumpAndSettle();
      expect(app.isFavorite('a'), isTrue);
      await tester.tap(find.text('紀錄'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏'));
      await tester.pumpAndSettle();
      expect(find.text('甲店'), findsOneWidget);
      await tester.tap(find.text('這餐'));
      await tester.pumpAndSettle();
      await app.confirmCurrent();
      await tester.pumpAndSettle();
      await tester.tap(find.text('紀錄'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('回報用餐'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('吃過，喜歡'));
      await tester.pumpAndSettle();
      expect(app.history.single.feedback, MealFeedback.liked);
      expect(find.text('吃過，喜歡'), findsOneWidget);
      await tester.tap(find.text('我的'));
      await tester.pumpAndSettle();
      expect(find.text('我的偏好'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small phone and large text keep primary actions reachable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
    await tester.pumpWidget(host(app, const AppShell(), scale: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('就吃這家'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('就吃這家').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('紀錄'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(host(app, const ColdStartScreen(), scale: 2));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('直接幫我決定'), 150);
    expect(find.text('直接幫我決定').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation supports large text and a throwing map handler', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
    await tester.pumpWidget(
      host(
        app,
        ConfirmScreen(
          place: fixtures.shopsFirst,
          isDemo: true,
          forceWebCopyLink: true,
          openMapsOverride: (_) async => throw StateError('no handler'),
        ),
        scale: 2,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('開啟地圖'), 150);
    await tester.tap(find.text('開啟地圖'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('再試一次'), 150);
    expect(find.text('再試一次').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final throws in [false, true]) {
    testWidgets(
      'map preview failure ($throws) remains retryable and never writes history',
      (tester) async {
        final app = fixtures.readyApp(() => DateTime(2026, 9, 18, 12));
        var calls = 0;
        await tester.pumpWidget(
          host(
            app,
            Scaffold(
              body: PlaceDetailsSheet(
                place: fixtures.shopsFirst,
                openMaps: (_) async {
                  calls++;
                  if (throws) throw StateError('no handler');
                  return false;
                },
              ),
            ),
          ),
        );
        await tester.tap(find.text('在 Google Maps 查看'));
        await tester.pumpAndSettle();
        expect(find.textContaining('請重試或複製連結'), findsOneWidget);
        await tester.tap(find.text('在 Google Maps 查看'));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(app.history, isEmpty);
        expect(app.rerollsUsedToday, 0);
      },
    );
  }
}
