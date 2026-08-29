/// 소셜 로그인 콜백 딥링크 파싱 — 순수 함수만 둔다.
///
/// `flutter_web_auth_2` 는 로그인이 끝나면 `heattrip://login-callback?token=...` 형태의
/// 문자열을 돌려준다. 이 문자열에서 JWT 만 뽑는 일은 플러그인·저장소·네트워크와 아무
/// 관계가 없으므로 `SocialLoginService.signIn` 밖으로 꺼내 단위 테스트 대상으로 만든다.
library;

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
