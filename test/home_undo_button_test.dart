import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tapping on-screen 復原「店名」 restores same restaurant + 復原 reason', (
    tester,
  ) async {
    final a = Place(
      id: 'demo_beef_noodle',
      name: '老王紅燒牛肉麵',
      lat: 25.0478,
      lng: 121.5170,
      rating: 4.5,
      isDemo: true,
      cuisineTags: const ['麵'],
    );
    final b = Place(
      id: 'demo_rice_box',
      name: '阿美健康便當',
      lat: 25.048,
      lng: 121.518,
      rating: 4.3,
      isDemo: true,
      cuisineTags: const ['飯'],
    );

    final app = AppState();
    app.prefs = const UserPrefs(coldStartDone: true);
    app.nearby = [a, b];
    app.current = Decision(
      place: a,
      reasonZh: '評分不錯又夠近',
      score: 0.9,
      mealSlot: '午餐',
    );
    app.status = AppLoadStatus.ready;
    app.isDemo = true;
    app.locationOk = true; // 避免示範橫幅佔高，復原鈕可點

    // 排除走真實 AppState 路徑（設定 pending），再測 Home 常駐文字鈕
    await app.excludeCurrentPlace();
    expect(app.current!.place.id, 'demo_rice_box');
    expect(app.hasPendingUndo, isTrue);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: HomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('阿美健康便當'), findsWidgets);
    await tester.scrollUntilVisible(
      find.byKey(const Key('undo_excluded_place')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('復原「老王紅燒牛肉麵」'), findsOneWidget);
    final undo = find.byKey(const Key('undo_excluded_place'));
    expect(undo, findsOneWidget);
    // 次要文字鈕，不是主 CTA FilledButton
    expect(tester.widget(undo), isA<TextButton>());

    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();

    expect(app.current!.place.id, 'demo_beef_noodle');
    expect(app.current!.place.name, '老王紅燒牛肉麵');
    expect(app.current!.reasonZh, '已復原你剛才排除的店');
    expect(app.hasPendingUndo, isFalse);
    await tester.scrollUntilVisible(
      find.text('老王紅燒牛肉麵'),
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('老王紅燒牛肉麵'), findsWidgets);
    expect(find.textContaining('已復原你剛才排除的店'), findsWidgets);
    expect(find.byKey(const Key('undo_excluded_place')), findsNothing);
  });
}
