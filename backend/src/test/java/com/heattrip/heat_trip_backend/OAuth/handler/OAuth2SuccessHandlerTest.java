package com.heattrip.heat_trip_backend.OAuth.handler;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.GoogleOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 소셜 로그인이 발급하는 토큰의 subject 규약을 잠근다 — 이슈 #5 완료 조건 6·9.
 *
 * <p>스프링 컨텍스트도 네트워크도 없다. 성공 핸들러 하나만 태우고 리다이렉트 URL 에 실린
 * 토큰을 직접 파싱한다.
 */
class OAuth2SuccessHandlerTest {

    /** 정확히 32바이트 — HS256 최소 키 길이. */
    private static final String SECRET = "test-only-secret-key-32bytes-min!!";

    /** 구글이 준 소셜 ID. 예전에는 이 값이 그대로 subject 였다. */
    private static final String PROVIDER_ID = "109876543210987654321";

    private static final long USER_ID = 42L;

    @Test
    @DisplayName("소셜 로그인이 발급한 토큰의 subject 는 users.id 인 \"42\" 이고 소셜 ID(google_...)가 아니다")
    void 발급토큰의_subject가_usersId다() throws Exception {
        String token = tokenFrom(principal(USER_ID));

        Claims claims = parse(token);

        assertThat(claims.getSubject())
                .as("authentication.getName() 은 provider_providerId 다 — 그걸 subject 로 쓰면 소셜 계정이 조회되지 않는다")
                .isEqualTo("42");
        assertThat(claims.getSubject())
                .doesNotStartWith("google_")
                .doesNotStartWith("kakao_")
                .doesNotContain(PROVIDER_ID);
        assertThat(claims.get("role", String.class)).isEqualTo("ROLE_USER");
    }

    @Test
    @DisplayName("users.id 를 모르는 principal 이 오면 토큰을 발급하지 않고 실패 딥링크로 돌려보낸다")
    void userId가없으면_토큰없이_실패딥링크로_보낸다() throws Exception {
        MockHttpServletResponse response = redirect(principal(null));

        assertThat(response.getRedirectedUrl())
                .as("sub=\"null\" 토큰이 앱 secure storage 에 저장되면 그 계정은 재로그인 전까지 영구 401 이다")
                .isEqualTo("heattrip://login-callback?error=account_state_invalid");
        assertThat(response.getRedirectedUrl()).doesNotContain("token=");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static CustomOAuth2User principal(Long userId) {
        Map<String, Object> attributes = Map.of("sub", PROVIDER_ID, "name", "프로브 사용자");
        OAuth2UserInfo userInfo = new GoogleOAuth2User(attributes);
        return new CustomOAuth2User(userInfo, attributes, userId, "ROLE_USER", false);
    }

    private static MockHttpServletResponse redirect(CustomOAuth2User principal) throws Exception {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", SECRET);
        ReflectionTestUtils.setField(provider, "expirationMillis", 3_600_000L);
        ReflectionTestUtils.invokeMethod(provider, "init");

        MockHttpServletResponse response = new MockHttpServletResponse();
        new OAuth2SuccessHandler(provider).onAuthenticationSuccess(
                new MockHttpServletRequest(), response,
                new OAuth2AuthenticationToken(principal, principal.getAuthorities(), "google"));
        return response;
    }

    private static String tokenFrom(CustomOAuth2User principal) throws Exception {
        String url = redirect(principal).getRedirectedUrl();
        assertThat(url).startsWith("heattrip://login-callback?token=");
        return url.substring(url.indexOf("token=") + "token=".length());
    }

    private static Claims parse(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8)))
                .build()
                .parseClaimsJws(token)
                .getBody();
    }
}
