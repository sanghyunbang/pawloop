import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// 위치를 쓸 수 없는 이유.
///
/// 예전에는 [LocationService.current] 가 이유 넷을 전부 `null` 하나로 뭉갰다. 화면은
/// "위치를 못 잡았다"까지만 알 수 있어서 **사용자가 무엇을 해야 하는지 말해 줄 수
/// 없었다** — 설정으로 가야 하는지, 앱 안에서 토글만 끄면 되는지, 그냥 밖으로 나가면
/// 되는지가 전부 다르다. (이슈 #160)
enum LocationDenial {
  /// 사용자가 프로필에서 '위치 정보 수집 일시 중단' 을 켰다. **앱 안에서 끌 수 있다.**
  pausedByUser,

  /// 기기의 위치 서비스 자체가 꺼져 있다. 앱 권한 문제가 아니라 OS 설정이다.
  serviceOff,

  /// 이번에 거부했다. 다음에 다시 물어볼 수 있다.
  denied,

  /// 영구 거부. **앱은 다시 물을 수 없고** 사용자가 OS 설정에서 직접 켜야 한다.
  deniedForever,

  /// 권한도 있고 서비스도 켜져 있는데 좌표가 안 온다 — 실내·터널·타임아웃.
  /// 사용자가 고칠 것이 없고 기다리거나 자리를 옮기면 된다.
  unavailable,
}

/// 현위치 조회 결과 — 좌표이거나, 못 쓴 이유다.
///
/// 둘 중 하나는 반드시 있고 둘 다 있지는 않다.
class LocationFix {
  final Position? position;
  final LocationDenial? denial;

  const LocationFix.found(Position this.position) : denial = null;
  const LocationFix.denied(LocationDenial this.denial) : position = null;

  bool get ok => position != null;
}

/// 위치 권한/현위치/위치 스트림을 단순화한 서비스.
class LocationService {
  /// 위치 정보 수집 일시 중단(사용자 설정).
  /// 위치정보법상 필수 기능 — 켜져 있으면 앱은 현위치를 조회/전송하지 않는다.
  static final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  /// 권한을 확보하고 현재 좌표를 얻는다. 못 얻으면 **이유를 함께** 준다.
  static Future<LocationFix> locate() async {
    if (paused.value) {
      return const LocationFix.denied(LocationDenial.pausedByUser);
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationFix.denied(LocationDenial.serviceOff);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return const LocationFix.denied(LocationDenial.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      return const LocationFix.denied(LocationDenial.denied);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      return LocationFix.found(pos);
    } catch (_) {
      return const LocationFix.denied(LocationDenial.unavailable);
    }
  }

  /// 현재 좌표. 실패면 null.
  ///
  /// 이유가 필요 없는 호출부(둘러보기 화면의 '내 주변' 정렬)를 위한 얇은 껍데기다.
  /// 이유를 화면에 띄워야 하면 [locate] 를 쓴다.
  static Future<Position?> current() async => (await locate()).position;

  /// 실시간 위치 스트림(산책 트래킹용). 5m 이동마다. 일시중지 시 빈 스트림.
  static Stream<Position> stream() {
    if (paused.value) return const Stream.empty();
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
    );
  }
}
