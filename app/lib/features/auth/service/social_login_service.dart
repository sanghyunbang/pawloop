import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';
import 'package:heat_trip_flutter/features/auth/data/auth_repository_impl.dart';
import 'package:heat_trip_flutter/features/auth/data/dto/auth_tokens.dart';

import 'oauth_callback.dart';

/// 소셜 로그인 왕복의 결과.
///
/// bool 이 아닌 이유: 화면이 실패 사유별로 다른 문장을 보여줘야 한다(#12 완료 조건 9).
/// 그리고 성공했을 때 **신규 가입 여부**를 함께 넘겨야 온보딩 분기를 할 수 있다.
@immutable
class SocialLoginResult {
  final SocialLoginOutcome outcome;

  /// 이번 인증으로 계정이 새로 생겼는가. 성공했을 때만 의미가 있다.
  ///
  /// #14 부터 **실제로 값이 온다.** 그전에는 딥링크에 `isNew` 를 실을 방법이 없어
  /// 항상 false 였고, 그래서 소셜 신규 가입자는 온보딩으로 가지 못했다. 이제 이 값은
  /// 코드 교환 응답(`AuthTokens.isNew`)에서 온다.
  final bool isNew;

  const SocialLoginResult(this.outcome, {this.isNew = false});

  bool get ok => outcome == SocialLoginOutcome.success;
}

/// 브라우저를 열어야 하는 인증 왕복. 테스트에서 갈아끼운다.
typedef WebAuthenticator =
    Future<String> Function({
      required String url,
      required String callbackUrlScheme,
    });

/// 1회용 코드를 토큰으로 바꾸는 왕복. 테스트에서 갈아끼운다.
typedef OAuthCodeExchanger =
    Future<AuthTokens?> Function({
      required String provider,
      required String code,
      required String state,
    });

/// 소셜 로그인 기능을 담당하는 클래스.
///
/// 외부 브라우저를 열어 소셜 로그인 후 앱으로 돌아오고, 콜백 URL 에 실려 온
/// **1회용 코드**를 서버에서 토큰으로 교환해 보안 저장소([AuthTokenStore])에 저장한다.
///
/// ## 흐름 (이슈 #14)
/// ```
/// ① state 생성 → ② /oauth2/authorization/{provider}?state=... 를 브라우저로 열기
/// ③ pawloop://login-callback?code=...&state=... 로 복귀
/// ④ 돌아온 state 가 ① 과 같은지 대조 (다르면 로그인 실패)
/// ⑤ POST /auth/oauth/{provider}/callback 으로 code → AuthTokens 교환
/// ⑥ 토큰 저장
/// ```
///
/// 예전에는 ③ 의 URL 에 액세스 토큰과 refresh 토큰이 실려 왔다. 커스텀 스킴은 어느
/// 앱이든 등록할 수 있고 그 URL 은 로그와 히스토리에 남으므로, 지금은 60초 살고 한 번
/// 쓰면 죽는 코드만 실린다.
///
/// 로깅 주의: 콜백 URL 에는 코드가, 교환 응답에는 토큰이 들어 있다.
/// 토큰도, 코드도, 콜백 URL 도, 예외 메시지 원문도 로그로 찍지 않는다(#61).
class SocialLoginService {
  const SocialLoginService();

  static Future<String> _webAuthenticate({
    required String url,
    required String callbackUrlScheme,
  }) => FlutterWebAuth2.authenticate(
    url: url,
    callbackUrlScheme: callbackUrlScheme,
  );

  /// 실제 인증 왕복. `flutter_web_auth_2` 는 플랫폼 채널이라 `flutter_test` 안에서는
  /// 그대로 부를 수 없다 — 취소·네트워크·서버 오류 세 갈래를 위젯 테스트로 확인하려면
  /// 이 자리가 필요하다(정책 #21).
  @visibleForTesting
  static WebAuthenticator authenticator = _webAuthenticate;

  /// 코드 교환용 리포지토리. `http.Client` 를 한 번만 만들어 재사용한다 —
  /// 로그인할 때마다 새 클라이언트를 만들면 연결 풀이 그만큼 쌓인다.
  static final AuthRepositoryImpl _repository = AuthRepositoryImpl();

  static Future<AuthTokens?> _exchange({
    required String provider,
    required String code,
    required String state,
  }) => _repository.exchangeOAuthCode(
    provider: provider,
    code: code,
    state: state,
  );

  /// 코드 → 토큰 교환. 테스트에서 갈아끼운다.
  @visibleForTesting
  static OAuthCodeExchanger exchanger = _exchange;

  /// 토큰 저장소. 실기기에서는 OS 보안 저장소(#8)다.
  @visibleForTesting
  static AuthTokenStore tokenStore = SecureAuthTokenStore();

  /// 테스트가 끝나면 원래 것으로 되돌린다.
  @visibleForTesting
  static void resetForTest() {
    authenticator = _webAuthenticate;
    exchanger = _exchange;
    tokenStore = SecureAuthTokenStore();
  }

  /// [provider]는 'kakao' · 'google' · 'apple'(#301). **네이버는 지원하지 않는다** — ADR-0010 이
  /// 보류로 확정했고 백엔드의 클라이언트 등록과 매핑 파서도 걷어냈다(#15).
  /// 되살리려면 ADR 을 먼저 고쳐야 한다.
  static Future<SocialLoginResult> signIn(String provider) async {
    if (kDebugMode) {
      debugPrint('[SocialLogin] 로그인 시작: $provider');
    }

    final baseUrl = Env.apiBase;

    // ① 이번 왕복의 state. 여기서 만들어 ④ 에서 이 값과 대조한다.
    //    지역 변수인 것이 중요하다 — 전역에 두면 두 로그인이 겹칠 때 뒤엣것이 앞엣것의
    //    기대값을 덮어써서, 대조가 우연히 성공하거나 우연히 실패한다.
    final state = newOAuthState();

    final String callbackUrl;
    try {
      // Spring Security 의 OAuth2AuthorizationRequestRedirectFilter 가
      // /oauth2/authorization/* 를 가로채 공급자로 보낸다. state 는 서버가 왕복 동안
      // 붙들었다가 딥링크에 그대로 실어 돌려준다(백엔드 OAuthAppStateFilter).
      // 딥링크 스킴은 "heattrip".
      //
      // ※ callbackUrl 을 로그로 찍지 마라 — URL 에 1회용 코드가 들어 있다.
      callbackUrl = await authenticator(
        url: '$baseUrl/oauth2/authorization/$provider?state=$state',
        callbackUrlScheme: 'pawloop',
      );
    } catch (e) {
      // 예외 메시지에 콜백 URL(=코드)이 섞여 들어올 수 있어 타입만 남긴다.
      final outcome = outcomeFromError(e);
      if (kDebugMode) {
        debugPrint('[SocialLogin] 로그인 중단: ${e.runtimeType} → ${outcome.name}');
      }
      return SocialLoginResult(outcome);
    }

    // ③④ 판정과 state 대조. 순수 함수라 단위 테스트가 이 규칙을 잠근다.
    final callback = resolveOAuthCallback(callbackUrl, state);
    if (!callback.ok) {
      if (kDebugMode) {
        debugPrint('[SocialLogin] 콜백이 성공이 아니다: ${callback.outcome.name}');
      }
      return SocialLoginResult(callback.outcome);
    }

    // ⑤ 코드 → 토큰. 여기가 소셜 경로에서 토큰이 앱에 도달하는 유일한 자리다.
    final AuthTokens? tokens;
    try {
      tokens = await exchanger(
        provider: provider,
        code: callback.code!,
        state: state,
      );
    } catch (e) {
      // 교환은 네트워크 왕복이다. 비행기 모드와 서버 오류를 같은 문장으로 뭉개지 않는다.
      final outcome = outcomeFromError(e);
      if (kDebugMode) {
        debugPrint('[SocialLogin] 코드 교환 실패: ${e.runtimeType} → ${outcome.name}');
      }
      return SocialLoginResult(outcome);
    }

    if (tokens == null) {
      // 401(재사용·만료·state 불일치)·429·계약 위반이 전부 여기다. 사용자 탓이 아니다.
      if (kDebugMode) {
        debugPrint('[SocialLogin] 코드 교환이 토큰을 돌려주지 않았다');
      }
      return const SocialLoginResult(SocialLoginOutcome.serverError);
    }

    // ⑥ 저장.
    try {
      await tokenStore.saveTokens(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
      );
    } catch (e) {
      // 저장에 실패하면 다음 실행에서 다시 로그인해야 한다. 성공이라고 말하지 않는다.
      if (kDebugMode) {
        debugPrint('[SocialLogin] 토큰 저장 실패: ${e.runtimeType}');
      }
      return const SocialLoginResult(SocialLoginOutcome.serverError);
    }

    if (kDebugMode) {
      debugPrint('[SocialLogin] 토큰 저장 완료');
    }
    return SocialLoginResult(SocialLoginOutcome.success, isNew: tokens.isNew);
  }
}
