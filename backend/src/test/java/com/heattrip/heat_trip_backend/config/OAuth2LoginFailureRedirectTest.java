package com.heattrip.heat_trip_backend.config;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.oauth2.client.web.OAuth2LoginAuthenticationFilter;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AuthenticationFailureHandler;
import org.springframework.security.web.authentication.SimpleUrlAuthenticationFailureHandler;
import org.springframework.test.util.ReflectionTestUtils;

import jakarta.servlet.Filter;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 배포된 필터체인이 실제로 실패를 딥링크로 돌려보내는지 확인한다. (이슈 #7)
 *
 * <p>{@code OAuth2FailureHandler} 단위 테스트만으로는 부족하다 — SecurityConfig 의
 * {@code .failureHandler(...)} 한 줄이 빠지면 그 핸들러는 만들어만 지고 아무도 부르지 않는다.
 * 그때 Spring Security 기본값 {@link SimpleUrlAuthenticationFailureHandler} 가 {@code /login?error}
 * 로 302 를 주고, 그 경로에 핸들러가 없어 전역 예외 처리기의 catch-all 로 떨어져 <b>500</b> 이 된다.
 * 여기서는 살아 있는 {@link FilterChainProxy} 에서 실제로 등록된 핸들러를 꺼내 직접 태운다.
 */
@SpringBootTest
class OAuth2LoginFailureRedirectTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private FilterChainProxy springSecurityFilterChain;

    private AuthenticationFailureHandler registeredFailureHandler() {
        for (SecurityFilterChain chain : springSecurityFilterChain.getFilterChains()) {
            for (Filter filter : chain.getFilters()) {
                if (filter instanceof OAuth2LoginAuthenticationFilter loginFilter) {
                    return (AuthenticationFailureHandler)
                            ReflectionTestUtils.getField(loginFilter, "failureHandler");
                }
            }
        }
        throw new IllegalStateException("OAuth2LoginAuthenticationFilter 가 필터체인에 없다.");
    }

    @Test
    @DisplayName("소셜 로그인 실패는 Spring 기본 /login?error 가 아니라 heattrip:// 딥링크로 끝난다")
    void oauth2LoginFailure_redirectsToAppDeepLink() throws Exception {
        AuthenticationFailureHandler handler = registeredFailureHandler();

        assertThat(handler)
                .as("failureHandler 를 붙이지 않으면 기본값이 /login?error 로 보내고 결국 500 이 된다")
                .isNotInstanceOf(SimpleUrlAuthenticationFailureHandler.class);

        MockHttpServletResponse response = new MockHttpServletResponse();
        handler.onAuthenticationFailure(new MockHttpServletRequest(), response,
                new OAuth2AuthenticationException(new OAuth2Error("email_already_registered"),
                        "이 이메일로 만들어진 계정이 이미 있습니다. provider=google"));

        assertThat(response.getRedirectedUrl())
                .isEqualTo("heattrip://login-callback?error=email_already_registered");
    }

    @Test
    @DisplayName("실패 리다이렉트에는 에러 코드만 실린다 — 이메일·토큰은 없다")
    void failureRedirect_carriesNoSecrets() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        registeredFailureHandler().onAuthenticationFailure(new MockHttpServletRequest(), response,
                new OAuth2AuthenticationException(new OAuth2Error("account_conflict"),
                        "bori@example.com 저장 실패 token=eyJhbGciOiJIUzI1NiJ9"));

        String redirect = response.getRedirectedUrl();
        assertThat(redirect).startsWith("heattrip://login-callback?error=");
        assertThat(redirect).doesNotContain("bori@example.com");
        assertThat(redirect).doesNotContain("eyJ");
    }
}
