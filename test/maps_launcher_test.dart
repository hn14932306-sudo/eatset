import 'package:eatset/models/place.dart';
import 'package:eatset/services/maps_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo place uses name+coords search URL without place_id', () {
    const place = Place(
      id: 'demo_beef_noodle',
      name: '老王紅燒牛肉麵',
      lat: 25.0478,
      lng: 121.5170,
      isDemo: true,
    );
    final uri = MapsLauncher.mapsSearchUri(place);
    expect(uri.host, 'www.google.com');
    expect(uri.path, '/maps/search/');
    expect(uri.queryParameters['api'], '1');
    expect(uri.queryParameters['query'], contains('老王紅燒牛肉麵'));
    expect(uri.queryParameters['query'], contains('25.0478'));
    expect(uri.queryParameters.containsKey('query_place_id'), isFalse);
  });

  test('real place includes query_place_id', () {
    const place = Place(
      id: 'ChIJrealplace',
      name: '真實店家',
      lat: 25.0,
      lng: 121.5,
      vicinity: '台北市',
      isDemo: false,
    );
    final uri = MapsLauncher.mapsSearchUri(place);
    expect(uri.queryParameters['query_place_id'], 'ChIJrealplace');
    expect(uri.queryParameters['query'], contains('真實店家'));
  });
}
