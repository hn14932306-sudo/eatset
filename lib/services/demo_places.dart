import 'dart:math' as math;

import '../models/place.dart';

/// 無 API 金鑰時的台灣風格示範店家（以使用者位置或台北車站為錨點）。
class DemoPlaces {
  DemoPlaces._();

  /// 預設錨點：台北車站附近。
  static const double anchorLat = 25.0478;
  static const double anchorLng = 121.5170;

  static List<Place> seededNear({double? userLat, double? userLng}) {
    final baseLat = userLat ?? anchorLat;
    final baseLng = userLng ?? anchorLng;

    final raw = <Place>[
      Place(
        id: 'demo_beef_noodle',
        name: '老王紅燒牛肉麵',
        lat: baseLat + 0.0012,
        lng: baseLng + 0.0008,
        rating: 4.5,
        userRatingsTotal: 842,
        types: const ['restaurant', 'food'],
        priceLevel: 1,
        openNow: true,
        vicinity: '忠孝西路一段',
        cuisineTags: const ['麵', '重口味', '內用'],
        isDemo: true,
      ),
      Place(
        id: 'demo_rice_box',
        name: '阿美健康便當',
        lat: baseLat - 0.0009,
        lng: baseLng + 0.0015,
        rating: 4.3,
        userRatingsTotal: 356,
        types: const ['meal_takeaway', 'restaurant'],
        priceLevel: 1,
        openNow: true,
        vicinity: '北平西路',
        cuisineTags: const ['飯', '清淡', '外帶', '快速'],
        isDemo: true,
      ),
      Place(
        id: 'demo_hotpot',
        name: '小火鍋研究所',
        lat: baseLat + 0.0021,
        lng: baseLng - 0.0011,
        rating: 4.4,
        userRatingsTotal: 512,
        types: const ['restaurant'],
        priceLevel: 2,
        openNow: true,
        vicinity: '許昌街',
        cuisineTags: const ['飯', '重口味', '內用'],
        isDemo: true,
      ),
      Place(
        id: 'demo_sushi',
        name: '日日壽司',
        lat: baseLat + 0.0004,
        lng: baseLng - 0.0020,
        rating: 4.6,
        userRatingsTotal: 1203,
        types: const ['restaurant', 'japanese'],
        priceLevel: 2,
        openNow: true,
        vicinity: '館前路',
        cuisineTags: const ['飯', '清淡', '內用'],
        isDemo: true,
      ),
      Place(
        id: 'demo_dumpling',
        name: '巷口煎餃專賣',
        lat: baseLat - 0.0015,
        lng: baseLng - 0.0006,
        rating: 4.2,
        userRatingsTotal: 289,
        types: const ['meal_takeaway', 'food'],
        priceLevel: 1,
        openNow: true,
        vicinity: '開封街',
        cuisineTags: const ['麵', '重口味', '外帶', '快速', '省錢'],
        isDemo: true,
      ),
      Place(
        id: 'demo_salad',
        name: '綠意沙拉碗',
        lat: baseLat + 0.0018,
        lng: baseLng + 0.0019,
        rating: 4.4,
        userRatingsTotal: 198,
        types: const ['restaurant', 'health'],
        priceLevel: 2,
        openNow: true,
        vicinity: '忠孝東路一段',
        cuisineTags: const ['飯', '清淡', '外帶', '快速'],
        isDemo: true,
      ),
      Place(
        id: 'demo_bbq',
        name: '夜市炭烤串燒',
        lat: baseLat - 0.0022,
        lng: baseLng + 0.0003,
        rating: 4.1,
        userRatingsTotal: 467,
        types: const ['restaurant', 'bar'],
        priceLevel: 1,
        openNow: true,
        vicinity: '南陽街',
        cuisineTags: const ['飯', '重口味', '內用'],
        isDemo: true,
      ),
      Place(
        id: 'demo_congee',
        name: '溫暖粥品屋',
        lat: baseLat + 0.0007,
        lng: baseLng + 0.0024,
        rating: 4.5,
        userRatingsTotal: 624,
        types: const ['restaurant'],
        priceLevel: 1,
        openNow: true,
        vicinity: '武昌街',
        cuisineTags: const ['飯', '清淡', '內用'],
        isDemo: true,
      ),
      Place(
        id: 'demo_ramen',
        name: '豚骨拉麵一番',
        lat: baseLat - 0.0005,
        lng: baseLng - 0.0018,
        rating: 4.7,
        userRatingsTotal: 1580,
        types: const ['restaurant', 'japanese'],
        priceLevel: 2,
        openNow: true,
        vicinity: '懷寧街',
        cuisineTags: const ['麵', '重口味', '內用'],
        isDemo: true,
      ),
      Place(
        id: 'demo_bubble_brunch',
        name: '早鳥蛋餅與咖啡',
        lat: baseLat + 0.0025,
        lng: baseLng - 0.0004,
        rating: 4.3,
        userRatingsTotal: 411,
        types: const ['cafe', 'bakery'],
        priceLevel: 1,
        openNow: true,
        vicinity: '鄭州路',
        cuisineTags: const ['飯', '清淡', '外帶', '快速'],
        isDemo: true,
      ),
      Place(
        id: 'demo_thai',
        name: '泰式打拋豬飯',
        lat: baseLat - 0.0011,
        lng: baseLng + 0.0022,
        rating: 4.4,
        userRatingsTotal: 733,
        types: const ['restaurant'],
        priceLevel: 1,
        openNow: true,
        vicinity: '漢口街',
        cuisineTags: const ['飯', '重口味', '外帶'],
        isDemo: true,
      ),
      Place(
        id: 'demo_veggie',
        name: '蔬食湯麵舖',
        lat: baseLat + 0.0010,
        lng: baseLng - 0.0025,
        rating: 4.2,
        userRatingsTotal: 156,
        types: const ['restaurant', 'vegetarian'],
        priceLevel: 1,
        openNow: true,
        vicinity: '延平南路',
        cuisineTags: const ['麵', '清淡', '內用'],
        isDemo: true,
      ),
    ];

    return raw.map((p) {
      final d = haversineMeters(baseLat, baseLng, p.lat, p.lng);
      return p.copyWith(distanceMeters: d);
    }).toList();
  }

  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const r = 6371000.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  static double _rad(double d) => d * math.pi / 180;
}
