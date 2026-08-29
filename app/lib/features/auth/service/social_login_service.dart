import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import 'package:heat_trip_flutter/core/config/env.dart';
import 'package:heat_trip_flutter/core/net/auth_token_store.dart';

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
  /// ⚠️ 2026-08 현재 딥링크에 `isNew` 가 실려 오지 않아 실제로는 항상 false 다 —
  /// [isNewFromCallback] 주석 참고. 계약이 채워지면 이 값이 저절로 살아난다.
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

/// 소셜 로그인 기능을 담당하는 클래스.
///
/// 외부 브라우저를 열어 소셜 로그인 후 앱으로 돌아오고, 콜백 URL에 실려 온
/// 토큰을 보안 저장소([AuthTokenStore])에 저장한다.
///
/// 로깅 주의: 콜백 URL 에는 토큰이 쿼리 파라미터로 들어 있다.
/// 토큰도, 콜백 URL 도, 예외 메시지 원문도 로그로 찍지 않는다(#61).
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

  /// 토큰 저장소. 실기기에서는 OS 보안 저장소(#8)다.
  @visibleForTesting
  static AuthTokenStore tokenStore = SecureAuthTokenStore();

  /// 테스트가 끝나면 원래 것으로 되돌린다.
  @visibleForTesting
  static void resetForTest() {
    authenticator = _webAuthenticate;
    tokenStore = SecureAuthTokenStore();
  }

  /// [provider]는 'google' · 'kakao' · 'naver' 중 하나.
  ///
  /// 흐름: `/oauth2/authorization/{provider}` 를 외부 브라우저로 열고 →
  /// `heattrip://login-callback?token=<AT>&refresh=<RT>` 로 돌아오면 →
  /// AT·RT 를 저장하고 [SocialLoginOutcome.success] 를 돌려준다.
  static Future<SocialLoginResult> signIn(String provider) async {
    if (kDebugMode) {
      debugPrint('[SocialLogin] 로그인 시작: $provider');
    }

    final baseUrl = Env.apiBase;

    final String result;
    try {
      // Spring Security 의 DefaultOAuth2AuthorizationRequestRedirectFilter 가
      // /oauth2/authorization/* 를 가로채 공급자로 보낸다.
      // 딥링크 스킴은 "heattrip".
      //
      // ※ result 를 로그로 찍지 마라 — URL 자체에 토큰이 들어 있다.
      result = await authenticator(
        url: '$baseUrl/oauth2/authorization/$provider',
        callbackUrlScheme: 'heattrip',
      );
    } catch (e) {
      // 예외 메시지에 콜백 URL(=토큰)이 섞여 들어올 수 있어 타입만 남긴다.
      final outcome = outcomeFromError(e);
      if (kDebugMode) {
        debugPrint('[SocialLogin] 로그인 중단: ${e.runtimeType} → ${outcome.name}');
      }
      return SocialLoginResult(outcome);
    }

    final outcome = outcomeFromCallback(result);
    if (outcome != SocialLoginOutcome.success) {
      if (kDebugMode) {
        debugPrint('[SocialLogin] 콜백이 성공이 아니다: ${outcome.name}');
      }
      return SocialLoginResult(outcome);
    }

    // #9 부터 딥링크는 `?token=<AT>&refresh=<RT>` 다. refresh 가 없다고 로그인을
    // 실패로 보지는 않는다 — AT 만으로도 로그인은 성립하고, 갱신만 못 한다.
    final token = tokenFromCallback(result)!;
    final refresh = refreshFromCallback(result);

    try {
      await tokenStore.saveTokens(accessToken: token, refreshToken: refresh);
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
    return SocialLoginResult(
      SocialLoginOutcome.success,
      isNew: isNewFromCallback(result),
    );
  }
}
