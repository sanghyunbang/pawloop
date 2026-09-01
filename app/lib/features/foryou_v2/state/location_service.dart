import 'package:geolocator/geolocator.dart';

import 'package:heat_trip_flutter/v2/data/location_service.dart' as v2;

/// 위치 권한/좌표를 단순화한 서비스 — **레거시(감정 지도·포유) 화면 전용.**
///
/// ## 이름이 같은 것이 둘이다
///
/// `v2/data/location_service.dart` 에도 `LocationService` 가 있고 그쪽이 정본이다.
/// 이 파일은 감정 지도·둘러보기·포유 화면만 쓴다(#164 정리 대상).
///
/// ## 왜 지금 고치는가
///
/// 이쪽은 **'위치 정보 수집 일시 중단' 토글을 보지 않았다.** 사용자가 프로필에서
/// 껐는데도 감정 지도·둘러보기는 `Geolocator.getCurrentPosition()` 을 그대로 불렀다.
/// 위치정보법 제24조의 이용중지 요구권으로 만든 기능이 **절반만 듣고 있었다.**
///
/// 합치지 않고 참조만 거는 이유는 이 파일이 곧 지워질 것이기 때문이다. 합치면 레거시
/// 화면 셋의 호출부를 손봐야 하는데, 그건 #164 가 화면째 걷어낼 때 함께 사라진다.
class LocationService {
  Future<(double? lat, double? lng)> getCurrentLatLng() async {
    // 정본 토글을 먼저 본다. 여기가 없으면 껐다고 믿는 사용자의 좌표가 계속 나간다.
    if (v2.LocationService.paused.value) return (null, null);

    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return (null, null);

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return (null, null);
    }
    if (perm == LocationPermission.deniedForever) {
      return (null, null);
    }

    final pos = await Geolocator.getCurrentPosition();
    return (pos.latitude, pos.longitude);
  }
}
