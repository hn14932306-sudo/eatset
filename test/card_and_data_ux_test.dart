import 'package:eatset/models/place.dart';
import 'package:eatset/models/user_prefs.dart';
import 'package:eatset/services/decision_engine.dart';
import 'package:eatset/screens/confirm_screen.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/widgets/decision_card.dart';
import 'package:eatset/widgets/open_status_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Map<String, dynamic> raw({Map<String, dynamic>? hours, Object? types}) => {
  'id': 'a',
  'displayName': {'text': '甲店'},
  'location': {'latitude': 25, 'longitude': 121},
  'types': types ?? ['restaurant'],
  'primaryTypeDisplayName': {'text': '拉麵店'},
  'currentOpeningHours': hours ?? {'openNow': true},
};

void main() {
  group('Google data we already pay for', () {
    test('closing time and type label come from the response', () {
      final p = PlacesService.parsePlace(
        raw(hours: {'openNow': true, 'nextCloseTime': '2026-09-19T13:30:00Z'}),
      );
      expect(p.closesAt!.toUtc(), DateTime.utc(2026, 9, 19, 13, 30));
      expect(p.typeLabel, '拉麵店');
    });

    test('a closing time is ignored when the place is not open', () {
      final p = PlacesService.parsePlace(
        raw(hours: {'openNow': false, 'nextCloseTime': '2026-09-19T13:30:00Z'}),
      );
      expect(p.closesAt, isNull);
    });

    test('garbage labels and times are dropped, not shown', () {
      final p = PlacesService.parsePlace({
        ...raw(hours: {'openNow': true, 'nextCloseTime': 'soon'}),
        'primaryTypeDisplayName': {'text': '  '},
      });
      expect(p.closesAt, isNull);
      expect(p.typeLabel, isNull);
    });

    test('official place types refine tags without breaking name matching', () {
      expect(
        PlacesService.parsePlace(raw(types: ['ramen_restaurant'])).cuisineTags,
        contains('麵'),
      );
      expect(
        PlacesService.parsePlace(
          raw(types: ['vegetarian_restaurant']),
        ).cuisineTags,
        contains('清淡'),
      );
      expect(
        PlacesService.parsePlace({
          ...raw(),
          'displayName': {'text': '阿嬤麵店'},
        }).cuisineTags,
        contains('麵'),
      );
    });
  });

  group('time until closing', () {
    final closes = DateTime(2026, 9, 19, 21, 30);
    Place open({DateTime? end}) => Place(
      id: 'a',
      name: '甲店',
      lat: 25,
      lng: 121,
      openNow: true,
      closesAt: end ?? closes,
    );

    test('reads as a countdown with the clock time', () {
      expect(
        open().openStatusLabel(DateTime(2026, 9, 19, 19, 15)),
        '目前營業中 · 還有 2 小時 15 分鐘打烊（21:30）',
      );
      expect(
        open().openStatusLabel(DateTime(2026, 9, 19, 20, 30)),
        '目前營業中 · 還有 1 小時打烊（21:30）',
      );
      expect(
        open().openStatusLabel(DateTime(2026, 9, 19, 21)),
        '目前營業中 · 還有 30 分鐘打烊（21:30）',
      );
    });

    test('never rounds up to more time than there is, or shows zero', () {
      expect(
        open().openStatusLabel(DateTime(2026, 9, 19, 21, 29, 20)),
        '目前營業中 · 還有 1 分鐘打烊（21:30）',
      );
      expect(Place.durationLabel(const Duration(seconds: 5)), '1 分鐘');
    });

    test(
      'once the closing time passes the place is closed, with no new request',
      () {
        final at = DateTime(2026, 9, 19, 21, 30);
        expect(open().isOpenAt(at), isFalse);
        expect(open().openStatusLabel(at), '已打烊');
        expect(open().timeUntilClose(at), isNull);
        expect(open().isOpenAt(DateTime(2026, 9, 19, 21, 29)), isTrue);
      },
    );

    test('a closing time a day or more away, or none, stays plain', () {
      final far = open(end: DateTime(2026, 9, 21, 3));
      expect(far.openStatusLabel(DateTime(2026, 9, 19, 19)), '目前營業中');
      const noTime = Place(
        id: 'a',
        name: '甲店',
        lat: 25,
        lng: 121,
        openNow: true,
      );
      expect(noTime.openStatusLabel(DateTime(2026, 9, 19, 19)), '目前營業中');
    });

    test('closed, unknown and demo keep their honest wording', () {
      const closed = Place(
        id: 'a',
        name: '甲店',
        lat: 25,
        lng: 121,
        openNow: false,
      );
      const unknown = Place(id: 'a', name: '甲店', lat: 25, lng: 121);
      const demo = Place(
        id: 'demo_a',
        name: '示範',
        lat: 25,
        lng: 121,
        isDemo: true,
      );
      final at = DateTime(2026, 9, 19, 19);
      expect(closed.openStatusLabel(at), '目前休息中');
      expect(unknown.openStatusLabel(at), '營業狀態未知 · 出發前請確認');
      expect(demo.openStatusLabel(at), '示範營業資訊');
    });

    test('a place past its closing time is never offered', () {
      final gone = Place(
        id: 'a',
        name: '甲店',
        lat: 25,
        lng: 121,
        rating: 4.5,
        userRatingsTotal: 100,
        priceLevel: 1,
        openNow: true,
        closesAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );
      final still = Place(
        id: 'b',
        name: '乙店',
        lat: 25,
        lng: 121,
        rating: 4.5,
        userRatingsTotal: 100,
        priceLevel: 1,
        openNow: true,
        closesAt: DateTime.now().add(const Duration(hours: 2)),
      );
      final kept = DecisionEngine().filterCandidates([
        gone,
        still,
      ], const UserPrefs());
      expect(kept.map((p) => p.id), ['b']);
    });

    testWidgets(
      'the countdown repaints itself and warns in the last half hour',
      (tester) async {
        var clock = DateTime(2026, 9, 19, 19, 15);
        await tester.pumpWidget(
          host(OpenStatusText(place: open(), now: () => clock)),
        );
        expect(find.text('目前營業中 · 還有 2 小時 15 分鐘打烊（21:30）'), findsOneWidget);
        final scheme = Theme.of(
          tester.element(find.byType(OpenStatusText)),
        ).colorScheme;
        Color? color() => tester
            .widget<Text>(find.byKey(const Key('place_open_status')))
            .style
            ?.color;
        expect(color(), scheme.primary);

        clock = DateTime(2026, 9, 19, 21, 5);
        await tester.pump(const Duration(seconds: 31));
        expect(find.text('目前營業中 · 還有 25 分鐘打烊（21:30）'), findsOneWidget);
        expect(color(), scheme.error);

        clock = DateTime(2026, 9, 19, 21, 31);
        await tester.pump(const Duration(seconds: 31));
        expect(find.text('已打烊'), findsOneWidget);
      },
    );

    testWidgets('places without a closing time run no timer', (tester) async {
      const plain = Place(
        id: 'a',
        name: '甲店',
        lat: 25,
        lng: 121,
        openNow: true,
      );
      await tester.pumpWidget(host(const OpenStatusText(place: plain)));
      await tester.pumpAndSettle();
      expect(find.text('目前營業中'), findsOneWidget);
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('decision card', () {
    final open = Place(
      id: 'a',
      name: '甲店',
      lat: 25,
      lng: 121,
      rating: 4.4,
      openNow: true,
      closesAt: DateTime.now().add(const Duration(hours: 2, minutes: 30)),
      typeLabel: '拉麵店',
      fetchedAt: DateTime.now(),
    );

    testWidgets('shows the countdown and the official type label', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          DecisionCard(
            decision: Decision(place: open, reasonZh: '理由', score: 1),
          ),
        ),
      );
      expect(find.textContaining('還有 2 小時'), findsOneWidget);
      expect(find.textContaining('打烊'), findsOneWidget);
      expect(find.byKey(const Key('place_type')), findsOneWidget);
      expect(find.text('拉麵店'), findsOneWidget);
    });

    testWidgets('without a closing time it keeps the plain wording', (
      tester,
    ) async {
      final plain = Place(
        id: 'a',
        name: '甲店',
        lat: 25,
        lng: 121,
        openNow: true,
        fetchedAt: DateTime.now(),
      );
      await tester.pumpWidget(
        host(
          DecisionCard(
            decision: Decision(place: plain, reasonZh: '理由', score: 1),
          ),
        ),
      );
      expect(find.text('目前營業中'), findsOneWidget);
    });

    testWidgets('a stored ID without live data says it will be re-checked', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          DecisionCard(
            decision: Decision(
              place: Place.reference('a'),
              reasonZh: '理由',
              score: 1,
            ),
          ),
        ),
      );
      expect(find.text('店家資訊待更新，確認前會重新查詢。'), findsOneWidget);
    });
  });

  group('confirm screen', () {
    testWidgets('shows the address so the user can navigate', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ConfirmScreen(
            place: Place(
              id: 'a',
              name: '甲店',
              lat: 25,
              lng: 121,
              vicinity: '台北市中正區一號',
            ),
          ),
        ),
      );
      expect(find.byKey(const Key('confirm_address')), findsOneWidget);
      expect(find.text('台北市中正區一號'), findsOneWidget);
      // No photo has been viewed, so nothing photo-related appears and no
      // request could have been made.
      expect(find.text('查看照片'), findsNothing);
      expect(find.byType(Image), findsNothing);
    });
  });
}
