/// 소셜 로그인 콜백 딥링크 파싱 — 순수 함수만 둔다.
///
/// `flutter_web_auth_2` 는 로그인이 끝나면 `heattrip://login-callback?token=...` 형태의
/// 문자열을 돌려준다. 이 문자열에서 JWT 만 뽑는 일은 플러그인·저장소·네트워크와 아무
/// 관계가 없으므로 `SocialLoginService.signIn` 밖으로 꺼내 단위 테스트 대상으로 만든다.
library;

import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;

/// 콜백 URL에서 JWT 를 뽑는다. 뽑을 수 없으면 예외 대신 null 을 돌려준다.
///
/// null 을 돌려주는 경우:
/// - URL 형식이 깨져 파싱조차 안 될 때
/// - 사용자가 동의를 거부해 `?error=access_denied` 만 실려 올 때
/// - `token` 파라미터가 아예 없거나 공백뿐일 때
///
/// 호출부는 null 을 "로그인 실패" 로 처리한다.
String? tokenFromCallback(String callbackUrl) {
  final Uri uri;
  try {
    uri = Uri.parse(callbackUrl);
  } on FormatException {
    return null;
  }

  // 공급자가 취소/거부를 알릴 때는 token 없이 error 만 온다.
  // token 과 error 가 함께 오는 변종도 있어, error 가 있으면 무조건 실패로 본다.
  final error = uri.queryParameters['error'];
  if (error != null && error.trim().isNotEmpty) return null;

  final token = uri.queryParameters['token'];
  if (token == null || token.trim().isEmpty) return null;
  return token;
}

/// 콜백 URL에서 refresh 토큰을 뽑는다. 뽑을 수 없으면 null.
///
/// #9 부터 딥링크가 `heattrip://login-callback?token=<AT>&refresh=<RT>` 이다.
/// 그전까지 앱은 `refresh` 파라미터를 버렸고, 그래서 액세스 토큰이 만료되는
/// 순간(1시간) 사용자는 조용히 로그아웃됐다 — 깨지는 게 아니라 작동하지 않는 것이라
/// 증상이 조용했다.
///
/// [tokenFromCallback] 과 규칙을 일부러 나눠 둔다.
/// - `error` 가 실려 오면 둘 다 실패다(같은 규칙).
/// - 그러나 **`refresh` 가 없다고 로그인을 실패시키지는 않는다.** 옛 서버·옛
///   딥링크로 돌아오는 경우 AT 만으로도 로그인은 성립하고, 갱신만 못 할 뿐이다.
///   그래서 호출부는 이 함수의 null 을 "갱신 불가" 로 다루지 "로그인 실패" 로
///   다루지 않는다.
///
/// refresh 토큰은 JWT 가 아니라 불투명 문자열이므로 **파싱하거나 검증하지 않는다.**
/// 값의 유효성은 서버만 안다.
String? refreshFromCallback(String callbackUrl) {
  final Uri uri;
  try {
    uri = Uri.parse(callbackUrl);
  } on FormatException {
    return null;
  }

  final error = uri.queryParameters['error'];
  if (error != null && error.trim().isNotEmpty) return null;

  final refresh = uri.queryParameters['refresh'];
  if (refresh == null || refresh.trim().isEmpty) return null;
  return refresh;
}

/// 콜백 URL에서 신규 가입 여부(`isNew`)를 읽는다. 없으면 **false**.
///
/// ## 왜 기본값이 false 인가
///
/// `isNew` 는 "이번 인증으로 계정이 새로 생겼다" 는 1회성 이벤트다. 모를 때 true 로
/// 떨어뜨리면 재로그인할 때마다 온보딩이 다시 뜬다 — 매번 반려동물 프로필을 새로
/// 등록하라고 요구하는 앱이 된다. 모를 때는 "새 사람이 아니다" 가 안전한 쪽이다.
///
/// ## ⚠️ 2026-08 현재 백엔드는 이 파라미터를 보내지 않는다
///
/// `OAuth2SuccessHandler` 가 만드는 딥링크는 `?token=<AT>&refresh=<RT>` 까지다.
/// 계약도 그렇게 적고 있다 — `AuthTokens` 의 `expiresIn`·`isNew`·`user` 가 소셜
/// 경로로 도달하려면 1회용 코드 교환(`POST /auth/oauth/{provider}/callback`, #14)이
/// 필요하다. 그래서 **소셜 신규 가입자는 지금 온보딩으로 가지 않는다.**
/// 이 함수는 그 파라미터가 붙는 날 앱을 고치지 않아도 되게 미리 열어 둔 자리이고,
/// 이메일 로그인 경로(`POST /auth/login` → `AuthTokens.isNew`)는 이미 값이 온다.
///
/// `true`/`1` 만 참으로 본다. 대소문자는 가리지 않는다.
bool isNewFromCallback(String callbackUrl) {
  final Uri uri;
  try {
    uri = Uri.parse(callbackUrl);
  } on FormatException {
    return false;
  }

  final raw = uri.queryParameters['isNew'];
  if (raw == null) return false;
  final normalized = raw.trim().toLowerCase();
  return normalized == 'true' || normalized == '1';
}

/// 소셜 로그인 시도의 결말. 화면이 **무엇을 말해야 하는지**를 정한다.
///
/// 예전에는 `Future<bool>` 하나였고 화면은 실패를 전부 "로그인에 실패했어요" 로
/// 뭉갰다. 사용자가 스스로 창을 닫은 것과 서버가 죽은 것에 같은 문장을 주면,
/// 취소한 사람은 앱이 고장 났다고 생각하고 서버가 죽었을 때는 이유도 모른 채
/// 같은 버튼을 반복해서 누른다.
enum SocialLoginOutcome {
  /// 토큰을 받아 저장까지 끝났다.
  success,

  /// 사용자가 브라우저를 닫았거나 공급자 동의 화면에서 거부했다. **실패가 아니다.**
  canceled,

  /// 요청이 서버에 닿지 못했다(비행기 모드·DNS·타임아웃).
  networkError,

  /// 그 밖 — 서버 오류, 계약과 다른 콜백, 플러그인 오류.
  serverError,
}

/// 콜백 URL 하나만 보고 결말을 판정한다. 순수 함수.
///
/// - `error` 파라미터가 취소 계열이면 [SocialLoginOutcome.canceled]
/// - 그 밖의 `error` 는 [SocialLoginOutcome.serverError]
/// - `token` 이 없으면 [SocialLoginOutcome.serverError] — 계약 위반이지 사용자 탓이 아니다
/// - 그 외 [SocialLoginOutcome.success]
SocialLoginOutcome outcomeFromCallback(String callbackUrl) {
  final Uri uri;
  try {
    uri = Uri.parse(callbackUrl);
  } on FormatException {
    return SocialLoginOutcome.serverError;
  }

  final error = uri.queryParameters['error']?.trim().toLowerCase();
  if (error != null && error.isNotEmpty) {
    // 공급자마다 철자가 다르다. 카카오/구글은 access_denied, 일부 SDK 는 user_cancelled.
    const canceledCodes = {
      'access_denied',
      'user_cancelled',
      'user_canceled',
      'cancelled',
      'canceled',
    };
    return canceledCodes.contains(error)
        ? SocialLoginOutcome.canceled
        : SocialLoginOutcome.serverError;
  }

  return tokenFromCallback(callbackUrl) == null
      ? SocialLoginOutcome.serverError
      : SocialLoginOutcome.success;
}

/// 던져진 예외를 결말로 분류한다. 순수 함수.
///
/// `flutter_web_auth_2` 는 사용자가 브라우저 탭을 닫으면 `PlatformException`
/// (`code: CANCELED`)을 던진다. 그것을 "서버 오류" 로 보여 주면 스스로 닫은 사용자에게
/// 앱이 고장 났다고 말하는 셈이다.
SocialLoginOutcome outcomeFromError(Object error) {
  if (error is PlatformException) {
    const canceledCodes = {'CANCELED', 'CANCELLED', 'USER_CANCELED'};
    return canceledCodes.contains(error.code.toUpperCase())
        ? SocialLoginOutcome.canceled
        : SocialLoginOutcome.serverError;
  }
  if (error is SocketException ||
      error is http.ClientException ||
      error is TimeoutException) {
    return SocialLoginOutcome.networkError;
  }
  return SocialLoginOutcome.serverError;
}
