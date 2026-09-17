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

/// 定位服務；失敗時回傳 null，由上層改用 Demo。
class LocationService {
  Future<UserLocation?> getCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return UserLocation(lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }
}
