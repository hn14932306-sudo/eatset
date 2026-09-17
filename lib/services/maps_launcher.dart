import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import '../models/place.dart';

/// 開啟 Google Maps 搜尋／導航。
///
/// Web：必須用 `platformDefault` + `webOnlyWindowName: '_blank'`，
/// 且避免在 `canLaunchUrl` 之後再開窗（async gap 會被瀏覽器擋成 about:blank）。
class MapsLauncher {
  /// 組出跨平台可用的 Maps 搜尋 URL（優先 place_id，Demo 用名稱＋座標）。
  static Uri mapsSearchUri(Place place) {
    final isDemo = place.isDemo || place.id.startsWith('demo_');
    if (isDemo) {
      final q = Uri.encodeComponent('${place.name} ${place.lat},${place.lng}');
      return Uri.parse('https://www.google.com/maps/search/?api=1&query=$q');
    }
    final query = Uri.encodeComponent(
      '${place.name} ${place.vicinity ?? ''}'.trim(),
    );
    final placeId = Uri.encodeComponent(place.id);
    return Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$query&query_place_id=$placeId',
    );
  }

  static Future<bool> openPlace(Place place) async {
    final target = mapsSearchUri(place);

    if (kIsWeb) {
      // 不要先 await canLaunchUrl：會讓 window.open 脫離使用者手勢。
      return launchUrl(
        target,
        mode: LaunchMode.platformDefault,
        webOnlyWindowName: '_blank',
      );
    }

    // Android / iOS：外部應用（Google Maps / 瀏覽器）
    if (await canLaunchUrl(target)) {
      return launchUrl(target, mode: LaunchMode.externalApplication);
    }
    // 仍嘗試開啟（部分裝置 canLaunch 偏保守）
    return launchUrl(target, mode: LaunchMode.externalApplication);
  }
}
