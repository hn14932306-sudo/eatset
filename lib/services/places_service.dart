import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_keys.dart';
import '../models/place.dart';
import 'demo_places.dart';
import 'location_service.dart';

/// Google Places Nearby Search（REST）+ Demo 後備。
///
/// **偏好「較高評分／營業中」**：本服務回傳 Nearby 原始結果；
/// [DecisionEngine.filterCandidates] 已排除 `openNow == false`，
/// 並對真實店家套用最低評分／評論數；[DecisionEngine.scorePlace] 再偏高評分。
/// 因此不在此加 `opennow` 查詢參數，避免營業中過少時整批 ZERO_RESULTS 掉進 Demo。
class PlacesService {
  PlacesService({
    http.Client? client,
    String? apiKey,
  })  : _client = client ?? http.Client(),
        _apiKeyOverride = apiKey;

  final http.Client _client;

  /// 測試用覆寫；正式路徑為 null → 走 [googlePlacesApiKey]。
  final String? _apiKeyOverride;

  static const _nearbyUrl =
      'https://maps.googleapis.com/maps/api/place/nearbysearch/json';

  /// 最大搜尋半徑（公尺）。
  static const int defaultRadiusMeters = 1200;

  String get _effectiveKey => _apiKeyOverride ?? googlePlacesApiKey;

  bool get _hasKey => _effectiveKey.isNotEmpty;

  /// 取得附近餐飲；無金鑰或 API 失敗時回傳 Demo。
  Future<PlacesResult> fetchNearby({
    UserLocation? location,
    int radiusMeters = defaultRadiusMeters,
  }) async {
    final lat = location?.lat ?? DemoPlaces.anchorLat;
    final lng = location?.lng ?? DemoPlaces.anchorLng;
    final usedDeviceLocation = location?.fromDevice ?? false;

    if (!_hasKey) {
      return PlacesResult(
        places: DemoPlaces.seededNear(userLat: lat, userLng: lng),
        isDemo: true,
        usedDeviceLocation: usedDeviceLocation,
        noteZh: usedDeviceLocation
            ? 'Demo 模式：以你的位置為中心載入示範店家'
            : 'Demo 模式：無定位／無 API 金鑰，使用台北示範店家',
      );
    }

    try {
      final uri = Uri.parse(_nearbyUrl).replace(queryParameters: {
        'location': '$lat,$lng',
        'radius': '$radiusMeters',
        'type': 'restaurant',
        'language': 'zh-TW',
        'key': _effectiveKey,
      });
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        return _demoFallback(
          lat,
          lng,
          usedDeviceLocation,
          'Places API HTTP ${res.statusCode}，已改用 Demo',
        );
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final status = body['status'] as String? ?? '';
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        return _demoFallback(
          lat,
          lng,
          usedDeviceLocation,
          _noteForApiStatus(status),
        );
      }
      final results = (body['results'] as List?) ?? const [];
      final places = <Place>[];
      for (final raw in results) {
        final m = raw as Map<String, dynamic>;
        final geo = m['geometry'] as Map<String, dynamic>?;
        final loc = geo?['location'] as Map<String, dynamic>?;
        if (loc == null) continue;
        final pLat = (loc['lat'] as num).toDouble();
        final pLng = (loc['lng'] as num).toDouble();
        final opening = m['opening_hours'] as Map<String, dynamic>?;
        final types = (m['types'] as List?)?.cast<String>() ?? const [];
        places.add(
          Place(
            id: m['place_id'] as String? ?? '${pLat}_$pLng',
            name: m['name'] as String? ?? '未命名店家',
            lat: pLat,
            lng: pLng,
            rating: (m['rating'] as num?)?.toDouble() ?? 0,
            userRatingsTotal: m['user_ratings_total'] as int? ?? 0,
            types: types,
            priceLevel: m['price_level'] as int?,
            openNow: opening?['open_now'] as bool?,
            vicinity: m['vicinity'] as String?,
            distanceMeters:
                DemoPlaces.haversineMeters(lat, lng, pLat, pLng),
            cuisineTags: _inferTags(m['name'] as String? ?? '', types),
          ),
        );
      }
      if (places.isEmpty) {
        return _demoFallback(
          lat,
          lng,
          usedDeviceLocation,
          '附近找不到店家，已改用 Demo',
        );
      }
      return PlacesResult(
        places: places,
        isDemo: false,
        usedDeviceLocation: usedDeviceLocation,
      );
    } catch (_) {
      return _demoFallback(
        lat,
        lng,
        usedDeviceLocation,
        '網路或 API 失敗，已改用 Demo',
      );
    }
  }

  /// 將 Places status 轉成清楚的繁中說明（含常見錯誤碼）。
  static String _noteForApiStatus(String status) {
    switch (status) {
      case 'REQUEST_DENIED':
        return 'Places API：REQUEST_DENIED（金鑰無效、未啟用 Places API，或限制不符），已改用 Demo';
      case 'OVER_QUERY_LIMIT':
        return 'Places API：OVER_QUERY_LIMIT（配額用盡），已改用 Demo';
      case 'INVALID_REQUEST':
        return 'Places API：INVALID_REQUEST（參數錯誤），已改用 Demo';
      case 'UNKNOWN_ERROR':
        return 'Places API：UNKNOWN_ERROR（伺服器暫時錯誤），已改用 Demo';
      case 'NOT_FOUND':
        return 'Places API：NOT_FOUND，已改用 Demo';
      default:
        return 'Places API：$status，已改用 Demo';
    }
  }

  PlacesResult _demoFallback(
    double lat,
    double lng,
    bool usedDeviceLocation,
    String note,
  ) {
    return PlacesResult(
      places: DemoPlaces.seededNear(userLat: lat, userLng: lng),
      isDemo: true,
      usedDeviceLocation: usedDeviceLocation,
      noteZh: note,
    );
  }

  static List<String> _inferTags(String name, List<String> types) {
    final tags = <String>[];
    final n = name.toLowerCase();
    if (n.contains('麵') ||
        n.contains('面') ||
        n.contains('拉麵') ||
        n.contains('ramen') ||
        n.contains('noodle')) {
      tags.add('麵');
    } else if (n.contains('飯') ||
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
        types.contains('health')) {
      tags.add('清淡');
    }
    if (n.contains('火鍋') ||
        n.contains('燒烤') ||
        n.contains('辣') ||
        n.contains('炸')) {
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
