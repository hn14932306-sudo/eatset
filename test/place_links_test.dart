import 'package:eatset/models/place.dart';
import 'package:eatset/services/places_service.dart';
import 'package:eatset/widgets/place_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Place place({String? menu, String? website}) => Place(
  id: 'real_a',
  name: '測試店',
  lat: 25,
  lng: 121,
  menuUri: menu == null ? null : Uri.parse(menu),
  websiteUri: website == null ? null : Uri.parse(website),
  menuNote: menu == null ? null : '官方菜單；品項以現場為準。',
);
Widget host(Place p, Future<bool> Function(Uri) open, {double scale = 1}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: PlaceLinks(place: p, openLink: open),
          ),
        ),
      ),
    );

void main() {
  testWidgets(
    'verified menu opens exact menu; website is never labelled menu',
    (tester) async {
      final opened = <Uri>[];
      Future<bool> open(Uri u) async {
        opened.add(u);
        return true;
      }

      await tester.pumpWidget(
        host(
          place(
            menu: 'https://example.com/menu',
            website: 'https://example.com',
          ),
          open,
        ),
      );
      await tester.tap(find.text('看菜單'));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://example.com/menu');
      expect(find.text('店家官網'), findsNothing);
      await tester.pumpWidget(
        host(place(website: 'https://example.com'), open),
      );
      expect(find.text('看菜單'), findsNothing);
      await tester.tap(find.text('店家官網'));
      await tester.pumpAndSettle();
      expect(opened.last.toString(), 'https://example.com');
    },
  );

  testWidgets(
    'missing and unsafe URLs fall back to Maps; failed links can retry at large text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var calls = 0;
      await tester.pumpWidget(
        host(
          place(
            menu: 'javascript:alert(1)',
            website: 'https://user:password@example.com',
          ),
          (uri) async {
            expect(uri.host, 'www.google.com');
            expect(uri.queryParameters['query_place_id'], 'real_a');
            calls++;
            return calls > 1;
          },
          scale: 2,
        ),
      );
      expect(find.text('看菜單'), findsNothing);
      expect(find.text('店家官網'), findsNothing);
      await tester.tap(find.text('更多照片與評論'));
      await tester.pumpAndSettle();
      expect(find.text('連結開啟失敗，請再試一次。'), findsOneWidget);
      await tester.tap(find.text('更多照片與評論'));
      await tester.pumpAndSettle();
      expect(find.text('連結開啟失敗，請再試一次。'), findsNothing);
      expect(calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  test('menu and website survive live copies but are not persisted', () {
    final p = PlacesService.parsePlace({
      'id': 'a',
      'location': {'latitude': 25, 'longitude': 121},
      'websiteUri': 'https://example.com',
      'menuUri': 'https://example.com/menu',
      'menuNote': '官方菜單',
    });
    expect(p.menuUri.toString(), 'https://example.com/menu');
    expect(p.copyWith(distanceMeters: 10).websiteUri, p.websiteUri);
    expect(p.copyWith(distanceMeters: 10).menuUri, p.menuUri);
    expect(p.toStorageJson(), {'id': 'a', 'isDemo': false});
    expect(p.toJson().containsKey('menuUri'), false);
    expect(p.toJson().containsKey('websiteUri'), false);
  });
}
