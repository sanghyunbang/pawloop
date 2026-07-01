import 'package:geolocator/geolocator.dart';

/// 위치 권한/현위치/위치 스트림을 단순화한 서비스.
class LocationService {
  /// 권한 확보 후 현재 좌표. 실패(거부/서비스 off)면 null.
  static Future<Position?> current() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (_) {
      return null;
    }
  }

  /// 실시간 위치 스트림(산책 트래킹용). 5m 이동마다.
  static Stream<Position> stream() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      );
}
