/// 앱 환경/설정 단일 진입점.
///
/// 값은 전부 **컴파일 타임 `--dart-define`** 으로 들어온다.
/// 예전에는 `.env` 를 `pubspec.yaml` 의 `assets` 에 올려 `flutter_dotenv` 로
/// 읽었는데, 에셋은 APK 안에 원본 그대로 실려 나간다 —
/// `unzip -p app-release.apk assets/flutter_assets/.env` 한 줄이면 값이 보였다.
/// 그래서 에셋 번들링을 걷어냈다. → 이슈 #29
///
/// 값을 한 번에 넣으려면 템플릿을 복사해 파일로 준다(파일은 gitignore 대상):
/// ```bash
/// cp dart-define.example.json dart-define.json
/// flutter run --dart-define-from-file=dart-define.json
/// ```
///
/// > **주의.** dart-define 은 *완화*이지 해결이 아니다. 컴파일 타임에 코드로
/// > 박힐 뿐, 문자열은 여전히 바이너리 안에 있고 `strings` 한 번이면 나온다.
/// > 쿼터·과금이 걸린 관광공사 키는 #40 에서 호출 자체를 백엔드 프록시로
/// > 옮겨야 앱에서 진짜로 사라진다. → 이슈 #29 (B)
class Env {
  const Env._();

  /// 로컬/스테이징 전환용 override. 운영값과 무관하게 최우선.
  static const _apiBaseOverride =
      String.fromEnvironment('API_BASE', defaultValue: '');

  /// 기본 베이스 URL(운영 원격). 예전 `.env` 의 같은 이름 키를 그대로 승계한다.
  static const _apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// 로컬 에뮬레이터에서 호스트(PC)의 localhost 를 가리키는 주소.
  static const localEmulator = 'http://10.0.2.2:8080';

  /// 백엔드 베이스 URL.
  ///
  /// 우선순위:
  ///  1) `--dart-define=API_BASE=...`
  ///  2) `--dart-define=API_BASE_URL=...`
  ///  3) [localEmulator] (안드로이드 에뮬레이터 → 호스트 로컬 백엔드)
  ///
  /// 예) 로컬 백엔드로 붙여 실행:
  ///   `flutter run --dart-define=API_BASE=http://10.0.2.2:8080`
  static String get apiBase {
    if (_apiBaseOverride.trim().isNotEmpty) return _apiBaseOverride.trim();
    if (_apiBaseUrl.trim().isNotEmpty) return _apiBaseUrl.trim();
    return localEmulator;
  }

  /// 현재 베이스가 로컬(에뮬레이터/localhost)인지.
  static bool get isLocal =>
      apiBase.contains('10.0.2.2') || apiBase.contains('localhost');

  /// 네이버 지도 Dynamic Map Client ID.
  /// 모바일 지도 SDK 는 Client ID 만 사용(시크릿 불필요). 패키지명 허용목록으로 보호됨.
  /// 비어 있으면 지도 SDK 초기화를 건너뛰고 지도 탭이 안내문만 표시한다.
  static const naverMapClientId =
      String.fromEnvironment('NAVER_MAP_CLIENT_ID', defaultValue: '');

  // 관광공사 서비스키와 호출자 표기가 여기 있었다. **이제 앱에 없다** (이슈 #40).
  //
  // --dart-define 으로 넣어도 문자열은 바이너리에 남아서 strings 한 번이면 나온다.
  // 그 키는 쿼터·과금이 걸린 자격증명이고, 폐기하려면 앱을 새로 배포해야 해서 즉시
  // 대응이 불가능했다. 지금은 서버가 대신 부르고 키는 서버 환경변수로만 존재한다.
  //
  // **여기에 다시 넣지 말 것.** 넣는 순간 완료 조건 1("릴리스 APK 를 훑어도 키가
  // 검색되지 않는다")이 깨지고, 그 사실은 아무 테스트도 알려 주지 않는다.
}
