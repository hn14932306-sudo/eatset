import 'dart:convert';
import 'package:eatset/services/backend_client.dart';
import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const newPlace = {
  'id': 'real_a',
  'displayName': {'text': '測試拉麵店'},
  'location': {'latitude': 25.034, 'longitude': 121.566},
  'rating': 4.6,
  'userRatingCount': 120,
  'priceLevel': 'PRICE_LEVEL_MODERATE',
  'currentOpeningHours': {'openNow': true},
  'businessStatus': 'OPERATIONAL',
  'formattedAddress': '台北市',
  'types': ['restaurant'],
};
void main() {
  const location = UserLocation(lat: 25.033, lng: 121.565);
  test('no backend or device location stays Demo without network', () async {
    var called = false;
    final client = MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    });
    expect(
      (await PlacesService(
        client: client,
        baseUrl: '',
      ).fetchNearby(location: location)).isDemo,
      isTrue,
    );
    expect(
      (await PlacesService(
        client: client,
        baseUrl: 'https://api.example',
      ).fetchNearby()).isDemo,
      isTrue,
    );
    expect(called, isFalse);
  });
  test(
    'New Places response is mapped through backend without a Google key',
    () async {
      final service = PlacesService(
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          expect(r.url.toString(), 'https://api.example/v1/nearby');
          expect(r.method, 'POST');
          expect(jsonDecode(r.body), {
            'lat': 25.033,
            'lng': 121.565,
            'radiusMeters': 1200,
          });
          expect(
            r.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('x-goog-api-key')),
          );
          return http.Response(
            jsonEncode({
              'places': [newPlace],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final result = await service.fetchNearby(location: location);
      final p = result.places.single;
      expect(result.isDemo, isFalse);
      expect(p.name, '測試拉麵店');
      expect(p.priceLevel, 2);
      expect(p.openNow, isTrue);
      expect(p.distanceMeters, isNotNull);
      expect(p.fetchedAt, isNotNull);
    },
  );
  test(
    'empty real results stay empty; errors never turn into fake real shops',
    () async {
      final empty = PlacesService(
        baseUrl: 'https://api.example',
        client: MockClient((_) async => http.Response('{"places":[]}', 200)),
      );
      expect((await empty.fetchNearby(location: location)).places, isEmpty);
      final failed = PlacesService(
        baseUrl: 'https://api.example',
        client: MockClient(
          (_) async => http.Response('{"error":{"code":"DAILY_LIMIT"}}', 429),
        ),
      );
      await expectLater(
        failed.fetchNearby(location: location),
        throwsA(isA<BackendException>()),
      );
    },
  );
  test(
    'details refresh maps new price and closed status with no invented distance',
    () async {
      final service = PlacesService(
        baseUrl: 'https://api.example',
        client: MockClient((r) async {
          expect(r.url.path, '/v1/places/real_a');
          return http.Response(
            jsonEncode({
              ...newPlace,
              'priceLevel': 'PRICE_LEVEL_EXPENSIVE',
              'businessStatus': 'CLOSED_PERMANENTLY',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final p = await service.fetchDetails('real_a');
      expect(p.priceLevel, 3);
      expect(p.openNow, isFalse);
      expect(p.distanceMeters, isNull);
    },
  );
  test('nonlocal HTTP backend is rejected before sending location', () async {
    var called = false;
    final service = PlacesService(
      baseUrl: 'http://api.example',
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );
    await expectLater(
      service.fetchNearby(location: location),
      throwsA(isA<BackendException>()),
    );
    expect(called, isFalse);
  });
}
