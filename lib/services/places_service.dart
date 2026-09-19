import 'package:http/http.dart' as http;

import '../models/place.dart';
import '../models/place_photo.dart';
import 'backend_client.dart';
import 'demo_places.dart';
import 'location_service.dart';

/// Nearby and details both use our backend; no Google key in the client.
class PlacesService {
  PlacesService({http.Client? client, String? baseUrl})
    : _backend = BackendClient(client: client, baseUrl: baseUrl);
  final BackendClient _backend;
  bool get isConfigured => _backend.isConfigured;
  static const int defaultRadiusMeters = 1200;

  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = defaultRadiusMeters,
  }) async {
    if (!isConfigured || location?.fromDevice != true) {
      return PlacesResult(
        places: DemoPlaces.seededNear(),
        isDemo: true,
        usedDeviceLocation: location?.fromDevice == true,
        noteZh: !isConfigured ? '示範模式 · 店家服務尚未連線' : '示範模式 · 開啟定位後可查附近店家',
      );
    }
    final data = await _backend.json(
      '/v1/nearby',
      body: {
        'lat': location!.lat,
        'lng': location.lng,
        'radiusMeters': radiusMeters,
      },
    );
    final places = (data['places'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map((m) => parsePlace(m, location: location))
        .toList();
    return PlacesResult(
      places: places,
      isDemo: false,
      usedDeviceLocation: true,
      noteZh: places.isEmpty ? '附近找不到符合條件的店家，請稍後再試' : null,
    );
  }

  Future<Place> fetchDetails(String placeId) async {
    if (!isConfigured) throw const BackendException('SERVICE_NOT_CONFIGURED');
    final data = await _backend.json(
      '/v1/places/${Uri.encodeComponent(placeId)}',
    );
    if (data['id'] != placeId) throw const BackendException('INVALID_RESPONSE');
    return parsePlace(data);
  }

  static Place parsePlace(Map<String, dynamic> m, {UserLocation? location}) {
    final loc = m['location'] as Map<String, dynamic>?;
    final id = m['id'];
    if (id is! String ||
        loc?['latitude'] is! num ||
        loc?['longitude'] is! num) {
      throw const BackendException('INVALID_RESPONSE');
    }
    final lat = (loc!['latitude'] as num).toDouble();
    final lng = (loc['longitude'] as num).toDouble();
    final name = (m['displayName'] as Map?)?['text'] as String? ?? '未命名店家';
    final types = (m['types'] as List? ?? []).cast<String>();
    const prices = {
      'PRICE_LEVEL_FREE': 0,
      'PRICE_LEVEL_INEXPENSIVE': 1,
      'PRICE_LEVEL_MODERATE': 2,
      'PRICE_LEVEL_EXPENSIVE': 3,
      'PRICE_LEVEL_VERY_EXPENSIVE': 4,
    };
    final closed =
        m['businessStatus'] != null && m['businessStatus'] != 'OPERATIONAL';
    final hours = m['currentOpeningHours'] as Map?;
    final openNow = closed ? false : hours?['openNow'] as bool?;
    return Place(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      rating: (m['rating'] as num?)?.toDouble() ?? 0,
      userRatingsTotal: (m['userRatingCount'] as num?)?.toInt() ?? 0,
      types: types,
      priceLevel: prices[m['priceLevel']],
      openNow: openNow,
      closesAt: openNow == true && hours?['nextCloseTime'] is String
          ? DateTime.tryParse(hours!['nextCloseTime'] as String)?.toLocal()
          : null,
      typeLabel: _label((m['primaryTypeDisplayName'] as Map?)?['text']),
      vicinity: m['formattedAddress'] as String?,
      distanceMeters: location?.fromDevice == true
          ? DemoPlaces.haversineMeters(location!.lat, location.lng, lat, lng)
          : null,
      cuisineTags: _inferTags(name, types),
      fetchedAt: DateTime.now(),
      websiteUri: safePhotoLink(m['websiteUri']),
      menuUri: safePhotoLink(m['menuUri']),
      menuNote: m['menuNote'] is String ? m['menuNote'] as String : null,
      photos: m['photos'] is List
          ? (m['photos'] as List)
                .whereType<Map<String, dynamic>>()
                .map((p) => PlacePhoto.fromGoogle(p, id))
                .whereType<PlacePhoto>()
                .where((p) => p.token.isNotEmpty)
                .take(3)
                .toList()
          : null,
      photosExpiresAt: m['photosExpiresAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(m['photosExpiresAt'] as int)
          : null,
      attributions: (m['attributions'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .toList(),
    );
  }

  void dispose() => _backend.dispose();

  static String? _label(Object? value) {
    final text = value is String ? value.trim() : '';
    return text.isEmpty || text.length > 20 ? null : text;
  }

  static List<String> _inferTags(String name, List<String> types) {
    final tags = <String>[];
    final n = name.toLowerCase();
    if (types.contains('ramen_restaurant') ||
        n.contains('麵') ||
        n.contains('面') ||
        n.contains('拉麵') ||
        n.contains('ramen') ||
        n.contains('noodle')) {
      tags.add('麵');
    } else if (types.contains('sushi_restaurant') ||
        n.contains('飯') ||
        n.contains('便當') ||
        n.contains('壽司') ||
        n.contains('rice') ||
        n.contains('don')) {
      tags.add('飯');
    }
    if (n.contains('清淡') ||
        n.contains('沙拉') ||
        n.contains('蔬') ||
        n.contains('粥') ||
        types.contains('health') ||
        types.contains('vegetarian_restaurant') ||
        types.contains('vegan_restaurant')) {
      tags.add('清淡');
    }
    if (n.contains('火鍋') ||
        n.contains('燒烤') ||
        n.contains('辣') ||
        n.contains('炸') ||
        types.contains('barbecue_restaurant')) {
      tags.add('重口味');
    }
    if (types.contains('meal_takeaway')) {
      tags.add('外帶');
      tags.add('快速');
    }
    return tags;
  }
}

class PlacesResult {
  const PlacesResult({
    required this.places,
    required this.isDemo,
    required this.usedDeviceLocation,
    this.noteZh,
  });

  final List<Place> places;
  final bool isDemo;
  final bool usedDeviceLocation;
  final String? noteZh;
}
