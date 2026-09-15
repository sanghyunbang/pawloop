import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 위치를 쓸 수 없는 이유.
///
/// 예전에는 [LocationService.current] 가 이유 넷을 전부 `null` 하나로 뭉갰다. 화면은
/// "위치를 못 잡았다"까지만 알 수 있어서 **사용자가 무엇을 해야 하는지 말해 줄 수
/// 없었다** — 설정으로 가야 하는지, 앱 안에서 토글만 끄면 되는지, 그냥 밖으로 나가면
/// 되는지가 전부 다르다. (이슈 #160)
enum LocationDenial {
  /// 아직 위치기반서비스 이용약관에 동의하지 않았다 — 이슈 #180.
  ///
  /// **가장 먼저 본다.** 권한도 서비스도 켜져 있는데 동의가 없으면 그건 우리가 수집하면
  /// 안 되는 상태다. 위치정보법 제15조 — 동의 없는 수집은 3년 이하 징역 또는 3천만원
  /// 이하 벌금이다.
  ///
  /// 로그인한 사람은 라우터가 동의 화면으로 붙잡으므로 여기 닿지 않는다. 여기 닿는 것은
  /// **"그냥 둘러보기" 로 들어온 게스트**다. 그 경로가 열려 있던 것을 이 값이 막는다 —
  /// `/explore` 는 공개 라우트인데 `explore_screen._boot` 이 현위치를 잡아
  /// `/api/places/nearby?lat=..&lng=..` 로 **우리 백엔드에** 보내고 있었다.
  notConsented,

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
  /// 위치기반서비스 이용약관에 동의했는가 — 이슈 #180.
  ///
  /// **기본값이 `false` 다.** 확인되기 전에는 안 한 것으로 본다 — 반대로 두면 앱이 뜨는
  /// 사이에 동의 없이 좌표가 나간다.
  ///
  /// 라우터가 인증 상태를 볼 때마다 여기에 써 준다. 화면이 아니라 여기 두는 이유는
  /// 좌표를 얻는 길이 여기 하나이기 때문이다 — 화면마다 검사를 두면 새 화면이 생길 때
  /// 한 곳을 빠뜨리고, 그 화면만 동의 없이 좌표를 보낸다.
  static final ValueNotifier<bool> consented = ValueNotifier<bool>(false);

  /// 위치 정보 수집 일시 중단(사용자 설정).
  ///
  /// 위치정보법 제24조의 이용중지 요구권을 화면으로 만든 것이다(프로필의 토글).
  ///
  /// **읽기 전용으로 쓴다.** 값을 바꿀 때는 [setPaused] 를 부른다 — 여기에 직접
  /// 대입하면 디스크에 안 남고, 앱을 껐다 켜면 중단이 풀린다. 실제로 그랬다:
  /// 이 값은 메모리 `ValueNotifier` 뿐이었고 저장하는 코드가 한 줄도 없었다.
  /// 사용자는 위치 수집을 껐다고 믿는 채로 다음 실행부터 다시 켜진 앱을 썼다.
  static final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  /// 중단 여부가 남는 자리. `_v1` 인 것은 이 앱의 다른 키들과 같은 규약이다.
  static const String pausedKey = 'location_paused_v1';

  /// 저장된 중단 여부를 되살린다. **`runApp` 전에 한 번** 부른다.
  ///
  /// 실패하면 중단이 아닌 상태로 시작한다 — 여기서 던지면 앱이 안 뜬다. 다만
  /// 조용히 넘기지는 않는다: 사용자가 끈 것을 못 살렸다는 사실은 로그에 남긴다.
  static Future<void> restorePaused() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      paused.value = prefs.getBool(pausedKey) ?? false;
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] 중단 설정을 못 읽었다: $e');
    }
  }

  /// 중단 여부를 바꾸고 **디스크에 남긴다.**
  ///
  /// 화면은 이것만 부른다. 저장에 실패하면 `false` 를 돌려주고 **메모리 값도 안
  /// 바꾼다** — 껐다고 표시해 놓고 다음 실행에 켜져 있으면, 화면이 거짓말한 것이
  /// 된다. 실패를 화면이 알아야 사용자에게 말할 수 있다.
  static Future<bool> setPaused(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wrote = await prefs.setBool(pausedKey, value);
      if (!wrote) return false;
      paused.value = value;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] 중단 설정을 못 남겼다: $e');
      return false;
    }
  }

  /// 권한이 새로 허용된 횟수. 화면이 뜬 뒤에 허용됐으면 배경에서 위치를 쓰던 카드들이
  /// 다시 시도한다 — 안 그러면 허용해 놓고도 앱을 껐다 켤 때까지 카드가 없다(#517).
  static final ValueNotifier<int> permissionRev = ValueNotifier<int>(0);

  /// 권한을 확보하고 현재 좌표를 얻는다. 못 얻으면 **이유를 함께** 준다.
  ///
  /// [prompt] 가 `false` 면 **OS 권한 대화상자를 띄우지 않는다.** 화면이 뜨자마자 배경에서
  /// 위치를 잡는 자리(홈의 안전 카드 · 오늘의 코스)를 위한 것이다. 거기서 물으면 사용자는
  /// **왜 묻는지 모르는 채** 대화상자를 만나고, 안드로이드는 두 번째 거부에서 영구 거부로
  /// 굳는다 — 그러면 앱은 다시 물을 수 없다. 설명을 먼저 보여 주는 자리
  /// (`LocationPrimingSheet`)를 지난 뒤에만 묻는다(#517).
  static Future<LocationFix> locate({bool prompt = true}) async {
    // 동의를 가장 먼저 본다. 권한 대화상자를 띄우기도 전이다 — 동의 없이 권한을 묻는
    // 것 자체가 순서가 뒤집힌 것이다.
    if (!consented.value) {
      return const LocationFix.denied(LocationDenial.notConsented);
    }
    if (paused.value) {
      return const LocationFix.denied(LocationDenial.pausedByUser);
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationFix.denied(LocationDenial.serviceOff);
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      if (!prompt) {
        return const LocationFix.denied(LocationDenial.denied);
      }
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
        // 방금 허용됐다 — 묻지 않고 기다리던 카드들이 이 신호로 다시 시도한다.
        permissionRev.value++;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      return const LocationFix.denied(LocationDenial.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      return const LocationFix.denied(LocationDenial.denied);
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: currentSettingsFor(defaultTargetPlatform),
      );
      return LocationFix.found(pos);
    } catch (_) {
      // 시간 제한(25초)에 걸린 것도 여기다 — "위치를 잡는 중" 을 영원히 돌리지 않는다(#335).
      return const LocationFix.denied(LocationDenial.unavailable);
    }
  }

  /// 현재 좌표. 실패면 null.
  ///
  /// 이유가 필요 없는 호출부(둘러보기 화면의 '내 주변' 정렬)를 위한 얇은 껍데기다.
  /// 이유를 화면에 띄워야 하면 [locate] 를 쓴다.
  static Future<Position?> current() async => (await locate()).position;

  /// 실시간 위치 스트림(산책 트래킹용). 5m 이동마다. 동의 전·일시중지 시 빈 스트림.
  ///
  /// 화면을 꺼도 이어진다(#335) — 안드로이드는 [notificationTitle]·[notificationText] 를 단
  /// 포그라운드 서비스 알림, iOS 는 `UIBackgroundModes/location`. 알림 문구는 스트림을 여는
  /// 순간에 정해지고 그 뒤에는 바뀌지 않는다(geolocator 가 갱신 API 를 주지 않는다).
  static Stream<Position> stream({
    String notificationTitle = '산책 기록 중',
    String notificationText = '화면을 꺼도 경로가 이어져요 · 탭하면 돌아가요',
  }) {
    if (!consented.value || paused.value) return const Stream.empty();
    return Geolocator.getPositionStream(
      locationSettings: settingsFor(defaultTargetPlatform, title: notificationTitle, text: notificationText),
    );
  }

  /// 첫 위치 한 번(트래킹 시작·지도 내 주변). 스트림과 같은 이유로 안드로이드는 GPS 제공자에서
  /// 직접 받고, 25초 안에 못 잡으면 포기한다 — 실내에서 "위치를 잡는 중" 이 영원히 돌던 자리다.
  static LocationSettings currentSettingsFor(TargetPlatform platform) {
    const limit = Duration(seconds: 25);
    switch (platform) {
      case TargetPlatform.android:
        return AndroidSettings(accuracy: LocationAccuracy.high, forceLocationManager: true, timeLimit: limit);
      case TargetPlatform.iOS:
        return AppleSettings(accuracy: LocationAccuracy.high, timeLimit: limit);
      default:
        return const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: limit);
    }
  }

  /// 플랫폼별 스트림 설정. 순수 함수라 테스트가 본다(`location_settings_test`).
  ///
  /// - 안드로이드: 포그라운드 서비스 + 알림. `enableWakeLock` 은 CPU 가 자도 위치 갱신이 오게,
  ///   `setOngoing` 은 산책 중에 알림을 지우면 서비스가 죽은 것으로 오해하지 않게.
  /// - iOS: WhenInUse 로 시작한 갱신을 백그라운드에서 이어 간다. 파란 표시를 숨기지 않는다.
  ///   `pauseLocationUpdatesAutomatically` 를 끈다 — 줄을 푸는 동안 멈춰 서면 iOS 가 스트림을 끊는다.
  /// - `ACCESS_BACKGROUND_LOCATION`(안드로이드) · Always(iOS) 는 요청하지 않는다: 앞에서 시작한
  ///   포그라운드 서비스면 충분하고, 그 권한은 심사에서 별도 사유를 요구한다.
  static LocationSettings settingsFor(TargetPlatform platform, {required String title, required String text}) {
    switch (platform) {
      case TargetPlatform.android:
        return AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          // GPS 제공자에서 직접 받는다. FusedLocation 은 포그라운드 서비스 안에서 갱신을
          // "too close / too fast" 로 막아 한 점도 오지 않았다(에뮬레이터 실측, #335). 산책 경로에
          // 네트워크·셀 위치가 섞이면 선이 튀기도 한다 — 어차피 GPS 만 쓰는 것이 맞다.
          forceLocationManager: true,
          foregroundNotificationConfig: ForegroundNotificationConfig(
            notificationTitle: title,
            notificationText: text,
            notificationChannelName: '산책 기록',
            enableWakeLock: true,
            setOngoing: true,
          ),
        );
      case TargetPlatform.iOS:
        return AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          activityType: ActivityType.fitness,
          allowBackgroundLocationUpdates: true,
          showBackgroundLocationIndicator: true,
          pauseLocationUpdatesAutomatically: false,
        );
      default:
        return const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
    }
  }

  /// 안드로이드 13+ 는 알림 권한이 없으면 포그라운드 서비스 알림이 안 보인다(서비스는 돈다).
  /// 트래킹을 시작하는 순간 한 번 묻는다. 거부해도 기록은 이어진다 — 알림만 없다.
  /// 테스트가 갈아 끼우는 자리.
  static Future<bool> Function() requestNotificationPermission = _requestNotificationPermission;

  static Future<bool> _requestNotificationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;
    try {
      return (await Permission.notification.request()).isGranted;
    } catch (e) {
      if (kDebugMode) debugPrint('[LocationService] 알림 권한을 못 물었다: $e');
      return false;
    }
  }
}
