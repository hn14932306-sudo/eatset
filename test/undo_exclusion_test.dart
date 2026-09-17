import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/providers/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Place place({
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('exclude then removeExcludedPlace restores same shop + 復原 reason',
      () async {
    final a = place(id: 'demo_a', name: '老王紅燒牛肉麵');
    final b = place(id: 'demo_b', name: '阿美健康便當', tags: const ['飯']);

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

    final excludedName = await app.excludeCurrentPlace();
    expect(excludedName, '老王紅燒牛肉麵');
    expect(app.prefs.excludedPlaceIds.contains('demo_a'), isTrue);
    // 排除後應換到另一家
    expect(app.current?.place.id, isNot('demo_a'));
    expect(app.current?.place.id, 'demo_b');

    await app.removeExcludedPlace('demo_a');

    expect(app.current, isNotNull);
    expect(app.current!.place.id, 'demo_a');
    expect(app.current!.place.name, '老王紅燒牛肉麵');
    expect(app.current!.reasonZh, contains('復原'));
    expect(app.prefs.excludedPlaceIds.contains('demo_a'), isFalse);
  });

  test('undo restores from pending cache even if nearby lacks the place',
      () async {
    final a = place(id: 'only_a', name: '獨家小館');
    final b = place(id: 'only_b', name: '隔壁店', tags: const ['飯']);

    final app = AppState();
    app.prefs = const UserPrefs(coldStartDone: true);
    app.nearby = [a, b];
    app.current = Decision(
      place: a,
      reasonZh: '先挑這家',
      score: 0.8,
      mealSlot: '午餐',
    );
    app.status = AppLoadStatus.ready;

    await app.excludeCurrentPlace();
    // 模擬 nearby 不再有 A（例如刷新後列表變了）
    app.nearby = [b];

    await app.removeExcludedPlace('only_a');

    expect(app.current!.place.id, 'only_a');
    expect(app.current!.place.name, '獨家小館');
    expect(app.current!.reasonZh, contains('復原'));
  });

  test('undo reconstructs minimal Place from excludedPlaceNames when needed',
      () async {
    final app = AppState();
    app.prefs = UserPrefs(
      coldStartDone: true,
      excludedPlaceIds: {'gone_id'},
      excludedPlaceNames: const {'gone_id': '記憶中的店'},
    );
    app.nearby = [
      place(id: 'other', name: '另一家', tags: const ['飯']),
    ];
    app.current = Decision(
      place: place(id: 'other', name: '另一家', tags: const ['飯']),
      reasonZh: '目前這家',
      score: 0.5,
      mealSlot: '午餐',
    );
    app.status = AppLoadStatus.ready;

    await app.removeExcludedPlace('gone_id');

    expect(app.current!.place.id, 'gone_id');
    expect(app.current!.place.name, '記憶中的店');
    expect(app.current!.reasonZh, contains('復原'));
  });
}
