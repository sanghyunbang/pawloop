// lib/v2/data/location_upload_policy.dart
//
// **좌표가 이 기기를 떠나도 되는가.** 그 판정이 앱 전체에서 여기 한 곳이다 — 이슈 #235.
//
// ## 왜 있나
//
// 위치기반서비스사업 신고(위치정보법 제9조)는 사업자등록이 있어야 할 수 있다. 그것이
// 없는 동안 배포하는 빌드는 `legal-lbs-compliance.md:28` 의 **A안(완전 온디바이스)** 이어야
// 한다 — 좌표가 단말을 떠나지 않으면 신고 대상이 아니라는 것이 그 문서의 전제다.
//
// ## 왜 화면마다 if 를 넣지 않았나
//
// 좌표가 나가는 자리가 **아홉 군데**였다. 손으로 훑고도 넷을 놓쳤다 — 산책 중 5m 마다
// 반복되는 조회, 산책 시작 지점, 큐의 자동 재전송, 그리고 서버 로그. 아홉 곳에 `if` 를
// 넣는 방식은 열 번째가 생기는 날 아무도 모른다.
//
// 그래서 **값을 죽이는 자리를 하나 두고** 모든 전송이 그것을 지나게 한다. 그러면
// "이 빌드가 좌표를 보내는가" 를 소스 스캔으로 셀 수 있다 —
// `location_upload_policy_test.dart` 가 그것을 센다.
//
// ## 왜 런타임 토글이 아닌가
//
// 런타임 스위치면 APK 안에 전송 코드가 **살아 있고 설정 하나로 켜진다.** "안 보냅니다" 를
// 증명하기 어렵다. 값은 `--dart-define` 으로 빌드에 박는다.
//
// 테스트만 예외인데 그 창구도 `assert` 안에 있다 — Dart 가 릴리스 빌드에서 `assert` 를
// 통째로 제거하므로 **배포본에는 갈아끼우는 갈래가 없다.** 자세한 이유는
// [LocationUploadPolicy.uploadsLocation] 에 적었다.
//
// **기본값이 안전한 쪽이다.** 아무것도 안 주면 온디바이스다. 보내려면 명시적으로 켜야 한다 —
// 실수로 안전하지 않은 빌드가 나가는 것보다 실수로 기능이 빠지는 편이 낫다.
//
// ## 신고를 마친 뒤
//
//   flutter build apk --dart-define=UPLOAD_LOCATION=true
//
// 코드는 그대로다. 이 파일이 존재하는 이유가 그것이다 — 되돌리기 위해 지웠던 코드를 다시
// 쓰는 일이 없게 한다.
library;

import 'package:flutter/foundation.dart';

/// 좌표가 서버로 나가도 되는가.
///
/// **이 클래스를 안 지나고 좌표를 보내는 코드는 없어야 한다.** 새로 만들었다면
/// `location_upload_policy_test.dart` 가 빨간불을 낸다.
class LocationUploadPolicy {
  const LocationUploadPolicy._();

  /// 빌드에 박히는 값. **기본은 꺼짐.**
  ///
  /// `--dart-define=UPLOAD_LOCATION=true` 로만 켜진다. 위치기반서비스사업 신고를
  /// 마친 뒤에 켠다(#200).
  static const bool _compiledIn =
      bool.fromEnvironment('UPLOAD_LOCATION', defaultValue: false);

  static bool _testOverride = _compiledIn;

  /// 서버 전송이 켜져 있는가.
  ///
  /// ## `assert` 안에서만 갈아끼운다
  ///
  /// 켜진 쪽도 테스트해야 한다 — 좌표를 `[경도, 위도]` 순으로 보내는지, 키 이름이
  /// 계약과 같은지 같은 것들은 정책과 무관한 계약이고 그걸 지키던 테스트가 있다.
  /// 그런데 컴파일 타임 상수는 한 프로세스 안에서 못 바꾼다.
  ///
  /// 그래서 `assert` 를 쓴다. **Dart 는 릴리스 빌드에서 `assert` 를 통째로 제거하므로**
  /// 배포본에는 이 갈래가 아예 없다 — 런타임 토글을 만들지 않으면서 테스트만 연다.
  /// 디버그·테스트에서만 [setForTest] 가 값을 바꿀 수 있다.
  ///
  /// `lib/` 안에서 [setForTest] 를 부르는 코드는 없어야 한다 —
  /// `location_upload_policy_test.dart` 가 그것을 센다.
  static bool get uploadsLocation {
    var value = _compiledIn;
    assert(() {
      value = _testOverride;
      return true;
    }());
    return value;
  }

  /// 테스트에서만. 릴리스에서는 [uploadsLocation] 이 이 값을 안 본다.
  @visibleForTesting
  static void setForTest(bool value) => _testOverride = value;

  /// 빌드에 박힌 값으로 되돌린다. `tearDown` 에서 부른다.
  @visibleForTesting
  static void resetForTest() => _testOverride = _compiledIn;

  /// 산책 경로를 실어도 되는가 — `POST /api/walks` 의 `path`·`pathT`.
  ///
  /// 꺼져 있으면 `null` 을 준다. 서버가 그 둘을 optional 로 받으므로 산책 자체는
  /// 그대로 저장된다({@code WalkRequest.path} 에 `@NotNull` 이 없다). 앱에서 죽는 기능도
  /// 없다 — 저장된 경로를 그리는 화면이 저장소에 없다.
  static List<List<double>>? pathForUpload(List<List<double>>? path) =>
      uploadsLocation ? path : null;

  /// 점별 시각. [pathForUpload] 와 짝이라 함께 죽는다.
  static List<int>? pathTimesForUpload(List<int>? pathT) =>
      uploadsLocation ? pathT : null;

  /// 걸은 길을 **코스로 남기고 이웃 코스를 보는** 기능이 사는가 — 이슈 #339.
  ///
  /// 코스의 선은 앱이 보내지 않는다. 서버가 그 산책의 `walk.path` 를 베껴 와 양 끝
  /// 100m 를 자른다(`CourseService.create`). 그런데 [pathForUpload] 가 꺼져 있으면
  /// **서버의 모든 산책이 `path IS NULL`** 이다 — 벨 선이 없으니 만들 코스도 없고,
  /// 아무의 빌드도 안 올리니 지도에 그릴 이웃 코스도 없다.
  ///
  /// 그래서 자리를 화면에서도 없앤다. 남겨 두면 6분을 걸어 온 사람이
  /// *"경로가 없는 기록이라 코스로 남길 수 없어요"* 를 본다 — 경로는 있었고 이 빌드가
  /// 안 보낸 것이라, 그 말은 사용자 입장에서 거짓이다.
  ///
  /// `legal-lbs-compliance.md` §1.3 의 A 행이 이것을 미리 적어 뒀다 —
  /// *"좌표를 전제한 서버 기능(경로 공유·경로 통계) 불가"*.
  /// `--dart-define=UPLOAD_LOCATION=true` 를 켜는 날 세 자리가 함께 돌아온다.
  static bool get sharesRoutes => uploadsLocation;

  /// 주변 장소를 물어도 되는가 — `GET /api/places/nearby?lat=..&lng=..`.
  ///
  /// **이 경로는 제품이 필요해서가 아니라 관광공사 서비스키를 앱에서 숨기려고 생겼다**(#40).
  /// 좌표를 격자 셀로 접어 보내는 절충안은 셀이 개인위치정보인지부터 정해야 해서
  /// (#235 §5) 여기서는 통째로 끈다.
  ///
  /// ## 끈다고 지도가 비지는 않는다 (이슈 #273)
  ///
  /// 예전에는 그랬다. 지금은 좌표를 **안 보내는** 다른 길이 있다 —
  /// `GET /api/places/catalog` 이 전국 한 벌을 주고, 거리 정렬·반경 필터는
  /// `PlaceCatalogRepository` 가 기기에서 한다. 요청에 좌표도 지역도 안 실린다.
  ///
  /// **그래서 그 경로는 이 정책을 지날 필요가 없다.** 게이트는 "무엇을 보낼까" 를
  /// 정하는 자리인데, 그쪽은 보낼 것이 아예 없다.
  static bool get canQueryNearbyPlaces => uploadsLocation;

  /// 커뮤니티 글에 장소를 달아도 되는가 — `PostInput.loc`·`contentId`.
  ///
  /// 사용자가 탭한 공개 장소의 이름·id 다. 단말의 GPS fix 가 아니지만, 그 목록 자체가
  /// 현위치 반경 조회의 결과라 "이 사람이 이 근처에 있었다" 를 함의할 수 있다. 판단이
  /// 갈리는 자리라 안전한 쪽으로 둔다.
  static String? placeNameForUpload(String? loc) => uploadsLocation ? loc : null;

  /// 위와 같다.
  static String? placeIdForUpload(String? contentId) =>
      uploadsLocation ? contentId : null;
}
