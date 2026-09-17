import 'dart:convert';

import 'package:eatset/services/location_service.dart';
import 'package:eatset/services/places_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const anchor = UserLocation(lat: 25.033, lng: 121.565, fromDevice: true);

  group('PlacesService', () {
    test('no key → demo fallback with note', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      });
      final svc = PlacesService(client: client, apiKey: '');
      final result = await svc.fetchNearby(location: anchor);

      expect(result.isDemo, isTrue);
      expect(result.places, isNotEmpty);
      expect(result.places.every((p) => p.isDemo), isTrue);
      expect(result.noteZh, contains('Demo'));
      expect(called, isFalse, reason: 'must not hit network without key');
    });

    test('OK results → isDemo false', () async {
      late Uri captured;
      final client = MockClient((request) async {
        captured = request.url;
        return http.Response(
          jsonEncode({
            'status': 'OK',
            'results': [
              {
                'place_id': 'ChIJtest1',
                'name': '測試拉麵店',
                'rating': 4.6,
                'user_ratings_total': 120,
                'types': ['restaurant', 'food'],
                'price_level': 2,
                'vicinity': '台北市',
                'opening_hours': {'open_now': true},
                'geometry': {
                  'location': {'lat': 25.034, 'lng': 121.566},
                },
              },
              {
                'place_id': 'ChIJtest2',
                'name': '測試便當',
                'rating': 4.2,
                'user_ratings_total': 80,
                'types': ['restaurant'],
                'opening_hours': {'open_now': false},
                'geometry': {
                  'location': {'lat': 25.032, 'lng': 121.564},
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final svc = PlacesService(client: client, apiKey: 'test-key-not-real');
      final result = await svc.fetchNearby(location: anchor);

      expect(result.isDemo, isFalse);
      expect(result.noteZh, isNull);
      expect(result.places, hasLength(2));
      expect(result.places.first.id, 'ChIJtest1');
      expect(result.places.first.name, '測試拉麵店');
      expect(result.places.first.openNow, isTrue);
      expect(result.places[1].openNow, isFalse);
      expect(result.places.every((p) => p.isDemo), isFalse);
      expect(captured.queryParameters['key'], 'test-key-not-real');
      expect(captured.queryParameters['type'], 'restaurant');
      expect(captured.queryParameters['language'], 'zh-TW');
      expect(captured.queryParameters.containsKey('opennow'), isFalse);
    });

    test('REQUEST_DENIED → demo fallback with clear note', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'status': 'REQUEST_DENIED',
            'error_message': 'The provided API key is invalid.',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final svc = PlacesService(client: client, apiKey: 'bad-key');
      final result = await svc.fetchNearby(location: anchor);

      expect(result.isDemo, isTrue);
      expect(result.places, isNotEmpty);
      expect(result.noteZh, contains('REQUEST_DENIED'));
      expect(result.noteZh, contains('已改用 Demo'));
    });

    test('OVER_QUERY_LIMIT → demo with status in note', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({'status': 'OVER_QUERY_LIMIT'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final svc = PlacesService(client: client, apiKey: 'test-key');
      final result = await svc.fetchNearby(location: anchor);

      expect(result.isDemo, isTrue);
      expect(result.noteZh, contains('OVER_QUERY_LIMIT'));
    });
  });
}
