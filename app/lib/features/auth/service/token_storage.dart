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

  /// 로그아웃 시 액세스/리프레시 토큰을 모두 지운다.
  static Future<void> clearToken() => SecureTokenStore.instance.clear();
}
