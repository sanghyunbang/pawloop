/// 소셜 로그인 콜백 딥링크 판정 — 순수 함수만 둔다.
///
/// `flutter_web_auth_2` 는 로그인이 끝나면
/// `heattrip://login-callback?code=<1회용 코드>&state=<앱이 만든 난수>` 형태의 문자열을
/// 돌려준다. 이 문자열을 판정하는 일은 플러그인·저장소·네트워크와 아무 관계가 없으므로
/// `SocialLoginService.signIn` 밖으로 꺼내 단위 테스트 대상으로 만든다.
/// (`FlutterWebAuth2.authenticate` 는 static 이라 스텁이 불가능하다 — 분리가 전제 조건이다.)
///
/// ## 2026-08: 딥링크에서 토큰이 사라졌다 (이슈 #14)
///
/// 예전에는 `?token=<AT>&refresh=<RT>` 였고 이 파일에 `tokenFromCallback` ·
/// `refreshFromCallback` · `isNewFromCallback` 이 있었다. 커스텀 스킴(`heattrip://`)은
/// 어느 앱이든 등록할 수 있고 URL 은 302 의 `Location` 헤더와 브라우저 히스토리에
/// 남는다 — 1시간짜리 액세스 토큰과 14일짜리 refresh 토큰이 그 채널로 나가고 있었다.
///
/// 지금 딥링크에 실리는 것은 60초 살고 한 번 쓰면 죽는 코드뿐이고, 토큰은
/// `POST /auth/oauth/{provider}/callback` 의 **응답 본문**으로만 온다.
/// 옛 함수들은 오지 않는 값을 찾는 코드라 지웠다 — 남겨 두면 테스트가 있는 죽은 코드가 된다.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:http/http.dart' as http;

/// 인증을 시작할 때 앱이 만드는 난수.
///
/// 이 값을 `GET /oauth2/authorization/{provider}?state=<이 값>` 으로 보내면 서버가 왕복
/// 동안 붙들었다가 딥링크에 그대로 실어 돌려준다. 앱은 돌아온 값이 **보낸 값과 같은지**
/// 대조한다 — 그것이 응답 바꿔치기와 CSRF 를 막는 표준 장치다.
///
/// 서버가 만들어 서버가 대조하면 아무것도 막지 못한다. **만든 쪽이 대조해야** 의미가 있다.
///
/// 문자 집합은 백엔드 `OAuthAppStateFilter` 의 화이트리스트(`[A-Za-z0-9_-]{1,128}`)와
/// 같다. 딥링크 쿼리에 그대로 실리므로 `&`·`#` 가 섞이면 파라미터를 하나 더 만들 수 있다.
/// 그래서 **패딩 없는** Base64URL 이다 — `=` 는 URL 인코딩이 필요하다.
///
/// [random] 은 테스트용 주입점이다. 기본값은 [Random.secure] —
/// `Random()` 은 예측 가능해서 이 자리에 쓰면 대조가 통과 의식이 된다.
String newOAuthState([Random? random]) {
  final rng = random ?? Random.secure();
  // 128bit. 공격자가 맞혀야 하는 값이고 URL 에 실리므로 짧을 이유가 없다.
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// 콜백 URL 하나와 기대하는 `state` 로부터 나온 판정.
@immutable
class OAuthCallbackResult {
  final SocialLoginOutcome outcome;

  /// [SocialLoginOutcome.success] 일 때만 non-null.
  ///
  /// 실패 판정이 코드를 함께 돌려주지 않는 것은 의도다 — 돌려주면 호출부가 실수로
  /// 그 코드를 교환에 쓸 수 있고, 그러면 `state` 대조가 있으나 마나가 된다.
  final String? code;

  const OAuthCallbackResult(this.outcome, {this.code});

  bool get ok => outcome == SocialLoginOutcome.success;
}

/// 콜백 URL 에서 1회용 코드를 뽑는다. 뽑을 수 없으면 null.
///
/// **`state` 를 보지 않는다.** 대조는 [resolveOAuthCallback] 의 일이고, 이 함수는
/// "코드가 실려 있는가" 만 답한다. 호출부는 대체로 [resolveOAuthCallback] 을 쓰면 된다.
String? codeFromCallback(String callbackUrl) {
  final params = _queryParametersOf(callbackUrl);
  if (params == null) return null;

  final code = params['code'];
  if (code == null || code.trim().isEmpty) return null;
  return code;
}

/// 쿼리 파라미터를 꺼낸다. 꺼낼 수 없으면 null. **던지지 않는다.**
///
/// `Uri.parse` 는 깨진 퍼센트 인코딩을 그 자리에서 거부하지 않는다 —
/// `uri.queryParameters` 가 **접근 시점에 지연 디코딩**하며 `FormatException` 을 던진다.
/// 그래서 `Uri.parse` 만 try/catch 로 감싸는 것으로는 부족하다. 실측:
///
/// ```
/// heattrip://login-callback?code=C&state=S&x=%E0%A4%A
///   -> FormatException: Missing extension byte (at offset 2)
/// ```
///
/// 이 예외는 [SocialLoginService.signIn] 이 감싸지 않는 자리에서 나와
/// **처리되지 않은 비동기 오류**가 됐다 — 사용자에게는 아무 반응 없는 버튼으로 보인다.
/// (`?code=%ZZ` 처럼 16진수가 아닌 경우는 던지지 않고 그대로 통과한다. 서버가 401 로
/// 거절하므로 무해하다. 던지는 것은 불완전한 UTF-8 다바이트 시퀀스다.)
Map<String, String>? _queryParametersOf(String callbackUrl) {
  try {
    return Uri.parse(callbackUrl).queryParameters;
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// 콜백 URL 하나와 기대하는 [expectedState] 로 결말을 판정한다. 순수 함수.
///
/// 판정 순서가 곧 규칙이다.
/// 1. URL 이 깨졌으면(파싱 실패 또는 **깨진 퍼센트 인코딩**) [SocialLoginOutcome.serverError].
/// 2. `error` 파라미터가 있으면 그 코드로 취소/서버오류를 가른다.
///    **`state` 대조보다 먼저** 본다 — 취소 딥링크에는 `state` 가 실려 오지 않으므로,
///    순서를 뒤집으면 스스로 창을 닫은 사용자에게 "서버에 문제가 있다" 고 말하게 된다.
/// 3. 돌아온 `state` 가 [expectedState] 와 <b>정확히</b> 같지 않으면 실패
///    ([SocialLoginOutcome.serverError]). 없음·빈 값·대소문자 차이 전부 불일치다.
///    [expectedState] 자체가 비어 있어도 실패다 — 앱이 생성을 건너뛴 상태를 조용히
///    통과시키면 검사가 있다고 말할 수 없다.
/// 4. `code` 가 없으면 실패. 계약 위반이지 사용자 탓이 아니다.
///
/// `state` 불일치에 별도 결말을 주지 않은 이유: 화면이 사용자에게 할 말이 서버 오류와
/// 같기 때문이다("잠시 후 다시 시도해 주세요"). 사용자에게 "state 가 다릅니다" 라고
/// 말해 봐야 할 수 있는 일이 없고, 결말을 늘리면 [loginFailureMessage] 류의 분기가
/// 그만큼 늘어난다.
OAuthCallbackResult resolveOAuthCallback(String callbackUrl, String expectedState) {
  // 파싱과 **디코딩**을 여기서 한 번에 끝낸다. 아래 어디에서도 uri.queryParameters 를
  // 다시 만지지 않는다 — 그 접근이 곧 지연 디코딩이고, 그것이 던지면 이 "순수 함수" 가
  // 결말 대신 예외를 밖으로 내보낸다.
  final params = _queryParametersOf(callbackUrl);
  if (params == null) {
    return const OAuthCallbackResult(SocialLoginOutcome.serverError);
  }

  final error = params['error']?.trim().toLowerCase();
  if (error != null && error.isNotEmpty) {
    // 공급자마다 철자가 다르다. 카카오/구글은 access_denied, 일부 SDK 는 user_cancelled.
    const canceledCodes = {
      'access_denied',
      'user_cancelled',
      'user_canceled',
      'cancelled',
      'canceled',
    };
    return OAuthCallbackResult(canceledCodes.contains(error)
        ? SocialLoginOutcome.canceled
        : SocialLoginOutcome.serverError);
  }

  // ── state 대조 ────────────────────────────────────────────────────────
  //
  // 이 두 줄이 응답 바꿔치기와 CSRF 를 막는 장치 전부다. 느슨하게 만들 자리가 아니다.
  //
  //  - `expectedState` 가 비어 있으면 **무조건 실패**다. 앱이 생성을 건너뛴 상태에서
  //    돌아온 값도 비어 있으면 `'' == ''` 로 통과해 버린다 — 검사가 있다고 말할 수
  //    없는 상태가 조용히 만들어진다.
  //  - 돌아온 값이 없으면(`null`) 불일치다. "없음" 은 일치가 아니다.
  //  - 비교는 정확 일치다. `toLowerCase()` 나 `trim()` 을 끼우면 공격자가 맞혀야 하는
  //    값의 공간이 줄고, 통과 의식이 된다.
  if (expectedState.isEmpty) {
    return const OAuthCallbackResult(SocialLoginOutcome.serverError);
  }
  if (params['state'] != expectedState) {
    return const OAuthCallbackResult(SocialLoginOutcome.serverError);
  }

  final code = params['code'];
  if (code == null || code.trim().isEmpty) {
    return const OAuthCallbackResult(SocialLoginOutcome.serverError);
  }
  return OAuthCallbackResult(SocialLoginOutcome.success, code: code);
}

/// 소셜 로그인 시도의 결말. 화면이 **무엇을 말해야 하는지**를 정한다.
///
/// 예전에는 `Future<bool>` 하나였고 화면은 실패를 전부 "로그인에 실패했어요" 로
/// 뭉갰다. 사용자가 스스로 창을 닫은 것과 서버가 죽은 것에 같은 문장을 주면,
/// 취소한 사람은 앱이 고장 났다고 생각하고 서버가 죽었을 때는 이유도 모른 채
/// 같은 버튼을 반복해서 누른다.
enum SocialLoginOutcome {
  /// 코드를 토큰으로 교환해 저장까지 끝났다.
  success,

  /// 사용자가 브라우저를 닫았거나 공급자 동의 화면에서 거부했다. **실패가 아니다.**
  canceled,

  /// 요청이 서버에 닿지 못했다(비행기 모드·DNS·타임아웃).
  networkError,

  /// 그 밖 — 서버 오류, 계약과 다른 콜백, `state` 불일치, 코드 교환 실패, 플러그인 오류.
  serverError,
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
