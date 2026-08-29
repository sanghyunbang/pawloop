import 'secure_token_store.dart';

/// JWT 토큰 접근용 얇은 위임 래퍼.
///
/// 저장 로직은 전부 [SecureTokenStore] 로 옮겼다. 이 클래스에는 더 이상
/// SharedPreferences 도, 키 상수도, 로깅도 없다 — 호출부 40여 곳을 한
/// 번에 고치지 않기 위해 이름만 남겨둔 것이다.
///
/// **새 코드는 `SecureTokenStore.instance` 를 직접 써라.**
/// 이 래퍼는 호출부가 정리되는 대로 삭제한다.
class TokenStorage {
  const TokenStorage._();

  /// JWT(액세스) 토큰을 보안 저장소에 저장한다.
  static Future<void> saveToken(String token) =>
      SecureTokenStore.instance.writeAccessToken(token);

  /// 저장된 JWT(액세스) 토큰을 읽는다. 없거나 읽기에 실패하면 null.
  static Future<String?> getToken() =>
      SecureTokenStore.instance.readAccessToken();

  // clearToken() 은 **삭제했다**(#12).
  //
  // 화면이 토큰만 지우고 `AuthState` 를 그대로 두면 "토큰은 없는데 status 는
  // authenticated" 인 상태가 남는다. 그 상태에서 로그인 화면으로 가면
  // `authRedirect` 가 홈으로 되튕겨, 로그아웃을 눌러도 로그인된 것처럼 보인다.
  // 주석으로 막으면 또 쓰이므로 아예 없애 **컴파일 에러**로 막는다.
  //
  // 로그아웃은 `AuthState.logout()`, 서버 세션이 이미 없는 경우(회원 탈퇴)는
  // `AuthState.clearLocalSession()` 을 쓴다.
}
