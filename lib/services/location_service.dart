import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class UserLocation {
  const UserLocation({
    required this.lat,
    required this.lng,
    this.fromDevice = true,
  });

  final double lat;
  final double lng;
  final bool fromDevice;
}

/// 定位失敗原因（供 App 內誠實說明）。
enum LocationFailureReason {
  /// 系統定位服務關閉（GPS / Location Services off）。
  serviceDisabled,
  /// 權限被拒（尚可再請求）。
  denied,
  /// 永久拒絕（需到系統設定開啟）。
  deniedForever,
  /// 其他錯誤（逾時、平台不支援等）。
  error,
}

/// 定位結果：成功帶座標，失敗帶原因。
class LocationResult {
  const LocationResult.success(this.location) : failure = null;

  const LocationResult.failure(this.failure) : location = null;

  final UserLocation? location;
  final LocationFailureReason? failure;

  bool get ok => location != null;
}

/// 定位服務；失敗時回傳帶原因的 [LocationResult]。
class LocationService {
  /// Debug／模擬器常用：台北車站附近（與 Demo 錨點一致）。
  static const UserLocation debugFallbackLocation = UserLocation(
    lat: 25.0478,
    lng: 121.5170,
    fromDevice: false,
  );

  /// 取得目前位置；會在 denied 時再請求一次權限。
  /// 模擬器常對 [getCurrentPosition] 逾時，故會後備 [getLastKnownPosition]；
  /// Debug 建置若仍失敗，使用固定測試座標（避免模擬器卡死在「定位失敗」）。
  Future<LocationResult> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationResult.failure(
          LocationFailureReason.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        return const LocationResult.failure(
          LocationFailureReason.deniedForever,
        );
      }
      if (permission == LocationPermission.denied) {
        return const LocationResult.failure(LocationFailureReason.denied);
      }

      Position? pos;
      try {
        pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 6),
          ),
        );
      } catch (e, st) {
        debugPrint('getCurrentPosition failed, try last known: $e\n$st');
      }

      pos ??= await Geolocator.getLastKnownPosition();

      if (pos == null &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.android) {
        try {
          pos = await Geolocator.getCurrentPosition(
            locationSettings: AndroidSettings(
              accuracy: LocationAccuracy.low,
              timeLimit: const Duration(seconds: 6),
              forceLocationManager: true,
            ),
          );
        } catch (e, st) {
          debugPrint('forceLocationManager getCurrentPosition failed: $e\n$st');
        }
        pos ??= await Geolocator.getLastKnownPosition();
      }

      if (pos != null) {
        return LocationResult.success(
          UserLocation(lat: pos.latitude, lng: pos.longitude),
        );
      }

      if (kDebugMode) {
        debugPrint(
          'Location unavailable; using debug fallback '
          '(${debugFallbackLocation.lat}, ${debugFallbackLocation.lng})',
        );
        return const LocationResult.success(debugFallbackLocation);
      }

      return const LocationResult.failure(LocationFailureReason.error);
    } catch (e, st) {
      debugPrint('getCurrentLocation failed: $e\n$st');
      if (kDebugMode) {
        return const LocationResult.success(debugFallbackLocation);
      }
      return const LocationResult.failure(LocationFailureReason.error);
    }
  }

  /// 開啟 App 設定頁（永久拒絕時）；Web／不支援平台不崩潰。
  Future<bool> openAppSettingsSafe() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (e, st) {
      debugPrint('openAppSettings failed: $e\n$st');
      return false;
    }
  }

  /// 開啟系統定位設定（服務關閉時）；Web／不支援平台不崩潰。
  Future<bool> openLocationSettingsSafe() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e, st) {
      debugPrint('openLocationSettings failed: $e\n$st');
      return false;
    }
  }
}
