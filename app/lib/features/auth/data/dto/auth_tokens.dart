// lib/features/auth/data/dto/auth_tokens.dart
//
// 계약 `AuthTokens` (docs/04-api/openapi.yaml) 의 앱쪽 표현.
//
// ## 왜 이 파일이 생겼나
//
// 2026-08 이전 `POST /auth/login` 의 응답 본문은 **JWT 원문 문자열**이었고,
// 앱은 `response.body` 를 그대로 토큰으로 저장했다. #10 이 응답을
//
//   {"accessToken":"...","refreshToken":"...","expiresIn":3600,"isNew":false,"user":{...}}
//
// 로 바꾸면서 그 코드는 **JSON 통째로를 토큰 자리에 저장**하게 됐다 —
// 그 상태로는 이후 모든 요청이 401 이다. 그래서 본문 해석을 한 곳으로 모은다.
//
// ## 왜 순수 함수인가
//
// 파싱은 네트워크도 저장소도 플랫폼 채널도 타지 않는다. [AuthTokens.tryParse] 하나만
// 떼어 단위 테스트할 수 있어야 한다(정책 #21, 선례: `oauth_callback.dart`).

import 'dart:convert';

/// `POST /auth/login` · `POST /auth/token/refresh` · 소셜 `callback` 의 200 본문.
///
/// 계약상 필수는 `accessToken` 과 `expiresIn` 둘뿐이다.
/// `refreshToken` 은 갱신 응답에서 항상 실리지만, `isNew`·`user` 는
/// 서버가 `@JsonInclude(NON_NULL)` 로 통째로 빼는 경로가 있다(갱신 응답).
class AuthTokens {
  /// Bearer 로 붙일 액세스 토큰(JWT).
  final String accessToken;

  /// 폐기 가능한 불투명 문자열(JWT 아님, 43자 Base64URL). 파싱하지 않는다.
  ///
  /// 갱신 때마다 **회전**하므로 응답의 새 값으로 반드시 교체 저장해야 한다.
  final String? refreshToken;

  /// 액세스 토큰의 남은 수명(초).
  final int expiresIn;

  /// 이번 인증으로 계정이 새로 생겼는지. 로그인 응답의 1회성 이벤트 속성이다.
  /// `POST /auth/login` 경로에서는 계약상 항상 false 다.
  final bool isNew;

  /// 계약 `User`. 갱신 응답에는 없다.
  final Map<String, dynamic>? user;

  const AuthTokens({
    required this.accessToken,
    required this.expiresIn,
    this.refreshToken,
    this.isNew = false,
    this.user,
  });

  /// 응답 본문 문자열을 [AuthTokens] 로 읽는다. 읽을 수 없으면 null.
  ///
  /// null 을 돌려주는 경우:
  /// - JSON 이 아님(구버전 서버가 아직 JWT 원문을 돌려주는 경우가 여기 걸린다)
  /// - 최상위가 객체가 아님
  /// - `accessToken` 이 없거나 문자열이 아니거나 공백뿐
  ///
  /// **예외를 던지지 않는다.** 호출부는 null 을 "로그인 실패" 로 다루면 된다 —
  /// 응답이 계약과 다를 때 앱이 죽는 것보다 재로그인으로 보내는 편이 낫다.
  static AuthTokens? tryParse(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    return fromJson(decoded);
  }

  /// 이미 디코드된 맵에서 읽는다. 규칙은 [tryParse] 와 같다.
  static AuthTokens? fromJson(Map<String, dynamic> json) {
    final access = json['accessToken'];
    if (access is! String || access.trim().isEmpty) return null;

    final refresh = json['refreshToken'];
    final expires = json['expiresIn'];
    final isNew = json['isNew'];
    final user = json['user'];

    return AuthTokens(
      accessToken: access,
      // 값이 있어도 빈 문자열이면 없는 것으로 본다 — 빈 RT 를 저장해 두면
      // 갱신이 "토큰 있음" 으로 판단해 400 을 받으러 나간다.
      refreshToken:
          (refresh is String && refresh.trim().isNotEmpty) ? refresh : null,
      // expiresIn 은 계약상 필수지만 없다고 로그인을 실패시키지는 않는다 —
      // 액세스 토큰 자체가 유효하면 앱은 동작하고, 만료는 401 로 알게 된다.
      expiresIn: expires is num ? expires.toInt() : 0,
      isNew: isNew is bool ? isNew : false,
      user: user is Map<String, dynamic> ? user : null,
    );
  }
}
