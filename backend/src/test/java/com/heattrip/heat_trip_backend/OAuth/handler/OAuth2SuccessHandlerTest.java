package com.heattrip.heat_trip_backend.OAuth.handler;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.GoogleOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;
import com.heattrip.heat_trip_backend.user.entity.RefreshToken;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

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
        RefreshTokenRepository refreshTokenRepository = savingRefreshTokenRepository();

        MockHttpServletResponse response = redirect(principal(null), refreshTokenRepository);

        assertThat(response.getRedirectedUrl())
                .as("sub=\"null\" 토큰이 앱 secure storage 에 저장되면 그 계정은 재로그인 전까지 영구 401 이다")
                .isEqualTo("heattrip://login-callback?error=account_state_invalid");
        assertThat(response.getRedirectedUrl()).doesNotContain("token=");
        assertThat(response.getRedirectedUrl())
                .as("실패 경로에서는 refresh 토큰도 나가지 않는다")
                .doesNotContain("refresh=");
        verify(refreshTokenRepository, never()).save(any(RefreshToken.class));
    }

    // ─────────────────────── refresh 토큰 (이슈 #9) ───────────────────────

    @Test
    @DisplayName("성공 딥링크에 액세스 토큰과 refresh 토큰이 함께 실리고 원장에는 그 사용자의 행이 저장된다")
    void 성공딥링크에_토큰과_refresh가_함께실린다() throws Exception {
        RefreshTokenRepository refreshTokenRepository = savingRefreshTokenRepository();

        String url = redirect(principal(USER_ID), refreshTokenRepository).getRedirectedUrl();

        assertThat(url)
                .as("계약에 적힌 현행 URL 접두사를 유지한다 — 순서를 뒤집으면 '?token=' 으로 매칭하는 파싱이 즉사한다")
                .startsWith("heattrip://login-callback?token=");
        assertThat(queryParam(url, "refresh"))
                .as("완료 조건 1 — 소셜 로그인 사용자에게 RT 가 도달할 유일한 경로다")
                .isNotBlank();

        ArgumentCaptor<RefreshToken> captor = ArgumentCaptor.forClass(RefreshToken.class);
        verify(refreshTokenRepository).save(captor.capture());
        assertThat(captor.getValue().getUserId()).isEqualTo(USER_ID);
        assertThat(captor.getValue().getTokenHash())
                .as("원장에 남는 것은 해시뿐이다 (완료 조건 8)")
                .isNotEqualTo(queryParam(url, "refresh"));
    }

    @Test
    @DisplayName("refresh 파라미터가 붙어도 token 파라미터를 쿼리로 읽으면 여전히 유효한 JWT 이고 subject 는 users.id 다")
    void refresh가붙어도_token파라미터는_온전한_JWT다() throws Exception {
        // 이 테스트가 substring 파싱을 금지한다. 'token=' 뒤를 전부 잘라 쓰면 &refresh=... 까지
        // 삼켜 서명 검증이 깨진다 — 앱(#11)이 겪게 될 문제와 같은 형태다.
        String url = redirect(principal(USER_ID), savingRefreshTokenRepository()).getRedirectedUrl();

        Claims claims = parse(queryParam(url, "token"));

        assertThat(claims.getSubject()).isEqualTo("42");
        assertThat(claims.get("role", String.class)).isEqualTo("ROLE_USER");
    }

    @Test
    @DisplayName("성공 리다이렉트 응답에 Cache-Control: no-store 가 붙는다")
    void 성공리다이렉트에_no_store가_붙는다() throws Exception {
        // 이 302 의 Location 헤더에는 자격증명이 둘 실려 있다. 캐시 경로 한 줄을 닫는다.
        MockHttpServletResponse response = redirect(principal(USER_ID), savingRefreshTokenRepository());

        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static CustomOAuth2User principal(Long userId) {
        Map<String, Object> attributes = Map.of("sub", PROVIDER_ID, "name", "프로브 사용자");
        OAuth2UserInfo userInfo = new GoogleOAuth2User(attributes);
        return new CustomOAuth2User(userInfo, attributes, userId, "ROLE_USER", false);
    }

    private static MockHttpServletResponse redirect(CustomOAuth2User principal) throws Exception {
        return redirect(principal, savingRefreshTokenRepository());
    }

    private static MockHttpServletResponse redirect(CustomOAuth2User principal,
                                                    RefreshTokenRepository refreshTokenRepository)
            throws Exception {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", SECRET);
        ReflectionTestUtils.setField(provider, "expirationMillis", 3_600_000L);
        ReflectionTestUtils.invokeMethod(provider, "init");

        RefreshTokenService refreshTokenService = new RefreshTokenService(
                refreshTokenRepository, mock(UserRepository.class), provider,
                Clock.systemDefaultZone(), 1_209_600_000L);

        MockHttpServletResponse response = new MockHttpServletResponse();
        new OAuth2SuccessHandler(provider, refreshTokenService).onAuthenticationSuccess(
                new MockHttpServletRequest(), response,
                new OAuth2AuthenticationToken(principal, principal.getAuthorities(), "google"));
        return response;
    }

    private static RefreshTokenRepository savingRefreshTokenRepository() {
        RefreshTokenRepository repository = mock(RefreshTokenRepository.class);
        when(repository.save(any(RefreshToken.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        return repository;
    }

    private static String tokenFrom(CustomOAuth2User principal) throws Exception {
        String url = redirect(principal).getRedirectedUrl();
        assertThat(url).startsWith("heattrip://login-callback?token=");
        // substring 방식은 &refresh= 가 붙는 순간 액세스 토큰을 잘못 잘라낸다.
        return queryParam(url, "token");
    }

    /** 딥링크 쿼리스트링에서 파라미터 하나를 꺼낸다. 값에는 URL 예약문자가 없다(Base64URL·JWT). */
    private static String queryParam(String url, String name) {
        String query = url.substring(url.indexOf('?') + 1);
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0 && pair.substring(0, eq).equals(name)) {
                return pair.substring(eq + 1);
            }
        }
        throw new AssertionError("딥링크에 " + name + " 파라미터가 없다: " + url);
    }

    private static Claims parse(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8)))
                .build()
                .parseClaimsJws(token)
                .getBody();
    }
}
