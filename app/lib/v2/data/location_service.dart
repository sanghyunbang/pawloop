import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// 위치 권한/현위치/위치 스트림을 단순화한 서비스.
class LocationService {
  /// 위치 정보 수집 일시 중단(사용자 설정).
  /// 위치정보법상 필수 기능 — 켜져 있으면 앱은 현위치를 조회/전송하지 않는다.
  static final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  /// 권한 확보 후 현재 좌표. 실패(거부/서비스 off/일시중지)면 null.
  static Future<Position?> current() async {
    if (paused.value) return null; // 일시중지 시 위치 미사용
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

  /// 실시간 위치 스트림(산책 트래킹용). 5m 이동마다. 일시중지 시 빈 스트림.
  static Stream<Position> stream() {
    if (paused.value) return const Stream.empty();
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    );
  }
}
