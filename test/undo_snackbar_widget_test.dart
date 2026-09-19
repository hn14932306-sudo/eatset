import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:eatset/widgets/decision_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 精簡 harness：DecisionCard + 「不要這家」→ SnackBar「復原」，
/// 對齊 home_screen 捕獲 AppState 後呼叫 removeExcludedPlace 的流程。
class _UndoHarness extends StatelessWidget {
  const _UndoHarness();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final decision = app.current;

    return Scaffold(
      body: Column(
        children: [
          if (decision != null)
            DecisionCard(decision: decision, showRealDistance: false)
          else
            const Text('無決策'),
          FilledButton(
            onPressed: () async {
              final captured = context.read<AppState>();
              final placeId = captured.current?.place.id;
              if (placeId == null) return;
              final name = await captured.excludeCurrentPlace();
              if (!context.mounted || name == null) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('已排除「$name」'),
                  action: SnackBarAction(
                    label: '復原',
                    onPressed: () {
                      captured.removeExcludedPlace(placeId);
                    },
                  ),
                ),
              );
            },
            child: const Text('不要這家'),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('tapping SnackBar 復原 restores same restaurant name on card', (
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

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: const MaterialApp(home: _UndoHarness()),
      ),
    );

    expect(find.text('老王紅燒牛肉麵'), findsWidgets);

    await tester.tap(find.text('不要這家'));
    await tester.pumpAndSettle();

    // 排除後卡片應換成另一家
    expect(find.text('阿美健康便當'), findsWidgets);
    expect(find.text('復原'), findsOneWidget);

    await tester.tap(find.text('復原'));
    await tester.pumpAndSettle();

    expect(find.text('老王紅燒牛肉麵'), findsWidgets);
    expect(find.textContaining('復原'), findsWidgets);
    expect(app.current!.place.id, 'demo_beef_noodle');
    expect(app.current!.reasonZh, contains('復原'));
  });
}
