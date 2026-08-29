// lib/core/net/auth_token_store.dart
//
// [AuthedClient] 가 토큰을 읽고 쓰는 **최소 인터페이스**.
//
// ## 왜 인터페이스를 하나 더 두나
//
// 실저장소인 `SecureTokenStore`(#8)는 `flutter_secure_storage` 위에 있고, 그것은
// 플랫폼 채널이다. `flutter_test` 안에서는 Keystore/Keychain 이 없으므로 그대로는
// 401→갱신→재시도 시나리오를 유닛 테스트할 수 없다. 그리고 이 저장소에는 mockito 가
// 없어(정책 #21) 생성 기반 목도 못 쓴다 — 손으로 만든 Fake 를 꽂을 자리가 필요하다.
//
// 인터페이스를 `core/net` 에 두는 이유: 이건 "인증 저장소" 의 전체 계약이 아니라
// **HTTP 계층이 필요로 하는 네 가지 동작**일 뿐이다. 저장 정책(키 이름·Keystore 옵션·
// 레거시 마이그레이션)은 계속 `SecureTokenStore` 의 것이다.

import 'package:heat_trip_flutter/features/auth/service/secure_token_store.dart';

/// HTTP 계층이 보는 토큰 저장소.
abstract class AuthTokenStore {
  /// 없거나 읽기에 실패하면 null. **예외를 던지지 않는다.**
  Future<String?> readAccessToken();

  /// 없거나 읽기에 실패하면 null. **예외를 던지지 않는다.**
  Future<String?> readRefreshToken();

  /// 갱신·로그인 결과를 저장한다.
  ///
  /// [refreshToken] 이 null 이면 **기존 값을 지우지 않고 그대로 둔다.**
  /// 서버가 회전한 새 RT 를 주지 않는 경로(옛 서버 등)에서 멀쩡한 RT 를
  /// 날려 재로그인시키지 않기 위해서다.
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  });

  /// 액세스·리프레시를 모두 지운다. 로그아웃 경로가 예외로 막히면 안 되므로
  /// 구현은 실패를 삼킨다.
  Future<void> clear();
}

/// 실제 앱이 쓰는 구현 — `SecureTokenStore`(OS 보안 저장소) 위임.
class SecureAuthTokenStore implements AuthTokenStore {
  final SecureTokenStore _store;

  SecureAuthTokenStore({SecureTokenStore? store})
    : _store = store ?? SecureTokenStore.instance;

  @override
  Future<String?> readAccessToken() => _store.readAccessToken();

  @override
  Future<String?> readRefreshToken() => _store.readRefreshToken();

  @override
  Future<void> saveTokens({
    required String accessToken,
    String? refreshToken,
  }) => _store.writeTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
  );

  @override
  Future<void> clear() => _store.clear();
}
