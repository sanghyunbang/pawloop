import 'package:flutter/foundation.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'oauth_callback.dart';
import 'secure_token_store.dart';
import 'package:heat_trip_flutter/core/config/env.dart';

/// 소셜 로그인 기능을 담당하는 클래스
/// 이 클래스는 외부 브라우저를 열어 소셜 로그인 후 앱으로 돌아오는 기능을 제공합니다.
/// 또한, URL에 포함된 JWT 토큰을 추출하여 보안 저장소([SecureTokenStore])에 저장합니다.
///
/// 로깅 주의: 콜백 URL 에는 토큰이 쿼리 파라미터로 들어 있다.
/// 토큰도, 콜백 URL 도, 예외 메시지 원문도 로그로 찍지 않는다.

class SocialLoginService {
  /// [provider]에는 'google', 'kakao', 'naver' 중 하나의 문자열이 들어갑니다.
  /// 예 : signIn('google' or 'kakao' or 'naver') -> 백엔드의 /oauth2/authorize 엔드포인트로 리다이렉트

  static Future<bool> signIn(String provider) async {
    if (kDebugMode) {
      debugPrint('[SocialLogin] 로그인 시작: $provider');
    }

    final baseUrl = Env.apiBase;

    try {
      // 1. 백엔드에 정의된 소셜 로그인 시작 URL을 생성 (0731 기준 여기서 먼저 정함 -> 이후 백단에서 이걸로 설정)
      // Spring Boot에서 DefaultOAuth2AuthroizationRequestRedirectionFilter 가 /oauth2/authorize/* 경로를 가로채서 동작
      final url = "$baseUrl/oauth2/authorization/$provider";

      // 2. 외부 브라우저를 열어 소셜 로그인 페이지로 이동
      // 로그인이 완료되면 앱으로 돌아오는 딥링크 스킴은 "heattrip"으로 지정

      final result = await FlutterWebAuth2.authenticate(
        url: url,
        callbackUrlScheme: "heattrip",
      );

      // 3. 브라우저에서 로그인 완료하면, 앱으로 리디렉션된 URL에서 JWT 토큰 추출
      // 예: heattrip://login-callback?token=eyJhbGciOi... 라면
      // result == 'heattrip://login-callback?token=...'
      // ※ result 를 로그로 찍지 마라 — URL 자체에 토큰이 들어 있다.

      final token = tokenFromCallback(result);

      if (token != null) {
        // 4. 추출한 JWT 토큰을 보안 저장소에 저장
        await SecureTokenStore.instance.writeAccessToken(token);
        if (kDebugMode) {
          debugPrint('[SocialLogin] 토큰 저장 완료');
        }
        return true;
      } else {
        // 예외 처리: 토큰이 없을 경우
        if (kDebugMode) {
          debugPrint('[SocialLogin] 콜백 URL에 token 파라미터가 없다');
        }
        return false;
      }
    } catch (e) {
      // 예외 처리: 인증 취소/URL 생성 실패 등
      // 예외 메시지에 콜백 URL(=토큰)이 섞여 들어올 수 있어 타입만 남긴다.
      if (kDebugMode) {
        debugPrint('[SocialLogin] 로그인 실패: ${e.runtimeType}');
      }
      return false;
    }
  }
}
