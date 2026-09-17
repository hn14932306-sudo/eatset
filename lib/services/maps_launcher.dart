import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';

/// 開啟 Google Maps 搜尋／導航。
class MapsLauncher {
  static Future<bool> openPlace(Place place) async {
    final query = Uri.encodeComponent('${place.name} ${place.vicinity ?? ''}');
    final geo = '${place.lat},${place.lng}';
    // 優先用搜尋 URL（跨平台穩健）
    final url = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query&query_place_id=${Uri.encodeComponent(place.id)}',
    );
    // Demo 店家沒有 place_id，改座標+名稱
    final fallback = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('${place.name}@$geo')}',
    );
    final target = place.isDemo || place.id.startsWith('demo_') ? fallback : url;
    if (await canLaunchUrl(target)) {
      return launchUrl(target, mode: LaunchMode.externalApplication);
    }
    return launchUrl(fallback, mode: LaunchMode.externalApplication);
  }
}
