import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 앱 환경/베이스 URL 단일 진입점.
///
/// 우선순위:
///  1) `--dart-define=API_BASE=...` (로컬/스테이징 전환용. 운영과 무관하게 override)
///  2) `.env`의 `API_BASE_URL` (기본 = 운영 원격)
///  3) `http://10.0.2.2:8080` (안드로이드 에뮬레이터 → 호스트 로컬 백엔드)
///
/// 예) 로컬 백엔드로 붙여 실행:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:8080
class Env {
  static const _fromDefine =
      String.fromEnvironment('API_BASE', defaultValue: '');

  /// 로컬 에뮬레이터에서 호스트(PC)의 localhost를 가리키는 주소.
  static const localEmulator = 'http://10.0.2.2:8080';

  static String get apiBase {
    if (_fromDefine.trim().isNotEmpty) return _fromDefine.trim();
    final fromEnv = dotenv.env['API_BASE_URL'];
    if (fromEnv != null && fromEnv.trim().isNotEmpty) return fromEnv.trim();
    return localEmulator;
  }

  /// 현재 베이스가 로컬(에뮬레이터/localhost)인지.
  static bool get isLocal =>
      apiBase.contains('10.0.2.2') || apiBase.contains('localhost');

  /// 네이버 지도 Dynamic Map Client ID (.env: NAVER_MAP_CLIENT_ID).
  /// 모바일 지도 SDK는 Client ID만 사용(시크릿 불필요). 패키지명 허용목록으로 보호됨.
  static String get naverMapClientId => dotenv.env['NAVER_MAP_CLIENT_ID'] ?? '';

  /// 공공데이터포털(관광공사) 서비스키. 이미 인코딩된 형태라 그대로 쿼리에 붙인다.
  /// (.env: YOUR_DECODING_SERVICE_KEY — 명칭과 달리 인코딩키가 들어있음)
  static String get tourServiceKey => dotenv.env['YOUR_DECODING_SERVICE_KEY'] ?? '';
}
