package com.heattrip.heat_trip_backend.OAuth.handler;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2Error;

import java.io.IOException;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 소셜 로그인 실패가 앱이 이해할 수 있는 형태로 끝나는지 잠근다. (이슈 #7)
 *
 * <p>이 핸들러가 없거나 SecurityConfig 에서 빠지면 Spring Security 기본값이 {@code /login?error}
 * 로 302 를 주고, 그 경로에 핸들러가 없어 결국 500 이 된다. 앱은 커스텀 스킴만 기다리므로
 * 로그인 시트가 멈춘 채 남는다.
 */
class OAuth2FailureHandlerTest {

    private final OAuth2FailureHandler handler =
            new OAuth2FailureHandler(new com.heattrip.heat_trip_backend.OAuth.OAuthSecurityProperties());

    private String redirectFor(AuthenticationException exception) throws IOException {
        MockHttpServletResponse response = new MockHttpServletResponse();
        handler.onAuthenticationFailure(new MockHttpServletRequest(), response, exception);
        return response.getRedirectedUrl();
    }

    private static OAuth2AuthenticationException oauthError(String code, String message) {
        return new OAuth2AuthenticationException(new OAuth2Error(code), message);
    }

    @Test
    @DisplayName("이메일 충돌 실패는 성공과 같은 딥링크로 error 코드를 실어 돌아간다")
    void emailCollision_redirectsToDeepLinkWithErrorCode() throws IOException {
        String redirect = redirectFor(oauthError("email_already_registered",
                "이 이메일로 만들어진 계정이 이미 있습니다. 처음 가입한 방식으로 로그인해 주세요. provider=google"));

        assertThat(redirect).isEqualTo("heattrip://login-callback?error=email_already_registered");
    }

    @Test
    @DisplayName("CustomOAuth2UserService 가 쓰는 나머지 실패 코드도 그대로 전달된다")
    void otherServiceErrorCodes_arePassedThrough() throws IOException {
        assertThat(redirectFor(oauthError("account_conflict", "계정 생성에 실패했습니다.")))
                .isEqualTo("heattrip://login-callback?error=account_conflict");
        assertThat(redirectFor(oauthError("missing_social_id", "소셜 공급자가 사용자 고유 ID 를 주지 않았습니다.")))
                .isEqualTo("heattrip://login-callback?error=missing_social_id");
        assertThat(redirectFor(oauthError("unsupported_provider", "지원하지 않는 소셜 공급자입니다: apple")))
                .isEqualTo("heattrip://login-callback?error=unsupported_provider");
    }

    @Test
    @DisplayName("리다이렉트 URL 에는 이메일·토큰·예외 메시지 원문이 들어가지 않는다")
    void redirect_carriesOnlyTheErrorCode() throws IOException {
        String redirect = redirectFor(oauthError("email_already_registered",
                "bori@example.com 로 만들어진 계정이 이미 있습니다. token=eyJhbGciOiJIUzI1NiJ9"));

        // 리다이렉트 URL 은 액세스 로그·리버스 프록시 로그에 그대로 남는다. (이슈 #6)
        assertThat(redirect).doesNotContain("bori@example.com");
        assertThat(redirect).doesNotContain("eyJ");
        assertThat(redirect).doesNotContain("token=");
        assertThat(redirect).isEqualTo("heattrip://login-callback?error=email_already_registered");
    }

    @Test
    @DisplayName("공급자가 준 이상한 error 코드는 딥링크에 주입되지 않고 기본 코드로 뭉개진다")
    void unsafeErrorCode_isReplacedWithDefault() throws IOException {
        // OAuth2Error 코드는 공급자 리다이렉트의 error 파라미터에서 올 수도 있다 — 신뢰 대상이 아니다.
        assertThat(redirectFor(oauthError("bad code&token=stolen", "…")))
                .isEqualTo("heattrip://login-callback?error=authentication_failed");
        assertThat(redirectFor(oauthError("../../other-scheme", "…")))
                .isEqualTo("heattrip://login-callback?error=authentication_failed");
        // 정상 코드는 대소문자·공백만 정규화해서 통과시킨다.
        assertThat(redirectFor(oauthError("  ACCESS_DENIED  ", "…")))
                .isEqualTo("heattrip://login-callback?error=access_denied");
    }

    @Test
    @DisplayName("OAuth2 예외가 아닌 인증 실패는 예외 클래스 이름조차 노출하지 않는다")
    void nonOAuthFailure_usesDefaultCode() throws IOException {
        assertThat(redirectFor(new BadCredentialsException("bori@example.com 자격 증명 오류")))
                .isEqualTo("heattrip://login-callback?error=authentication_failed");
    }
}
