package com.heattrip.heat_trip_backend.OAuth.jwt;

import com.heattrip.heat_trip_backend.OAuth.principal.AuthenticatedUser;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.util.Date;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 필터가 인증을 <b>어떻게 거절하는지</b>를 잠근다 — 이슈 #5.
 *
 * <p>거절 방식이 계약이다. 필터는 401 을 직접 만들지 않고, 응답에도 손대지 않고,
 * 예외를 밖으로 던지지도 않는다. {@code SecurityContext} 를 채우지 않고 체인을 계속 진행시킬 뿐이다.
 * 그 뒤는 {@code SecurityConfig} 의 {@code anyRequest().authenticated()} 와
 * {@code HttpStatusEntryPoint(UNAUTHORIZED)} 가 맡는다 — 인가 경계를 한 곳에 둔다.
 *
 * <p>스프링 컨텍스트가 필요 없다.
 */
class JWTAuthenticationFilterTest {

    /** 정확히 32바이트 — HS256 최소 키 길이. */
    private static final String SECRET = "test-only-secret-key-32bytes-min!!";

    private final JWTProvider jwtProvider = newProvider();
    private final JWTAuthenticationFilter filter = new JWTAuthenticationFilter(jwtProvider);

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    @Test
    @DisplayName("정상 토큰이면 principal 이 AuthenticatedUser(42, ROLE_USER) 이고 권한도 함께 실린다")
    void 정상토큰이면_principal이_AuthenticatedUser다() throws Exception {
        Authentication authentication = authenticate(bearer(jwtProvider.createAccessToken(42L, "ROLE_USER")));

        assertThat(authentication).isNotNull();
        assertThat(authentication.getPrincipal())
                .as("principal 을 문자열로 두면 findByEmail(principal) 이 영원히 컴파일된다 — 그게 이 이슈의 버그였다")
                .isEqualTo(new AuthenticatedUser(42L, "ROLE_USER"));
        assertThat(authentication.getAuthorities())
                .extracting(GrantedAuthority::getAuthority)
                .containsExactly("ROLE_USER");
        assertThat(authentication.getDetails())
                .as("요청 정보(IP 등)는 계속 실어 둔다")
                .isNotNull();
    }

    @Test
    @DisplayName("Authorization 헤더가 없으면 인증을 채우지 않고 체인을 그대로 진행시킨다")
    void 헤더가없으면_인증을채우지않는다() throws Exception {
        assertRejectedSilently(null);
    }

    @Test
    @DisplayName("Bearer 가 아닌 인증 방식(Basic)이면 인증을 채우지 않는다")
    void Basic헤더면_인증을채우지않는다() throws Exception {
        assertRejectedSilently("Basic dXNlcjpwYXNz");
    }

    @Test
    @DisplayName("Bearer 뒤가 JWT 가 아니면 인증을 채우지 않는다")
    void 형식이깨진토큰이면_인증을채우지않는다() throws Exception {
        assertRejectedSilently("Bearer not-a-jwt");
    }

    @Test
    @DisplayName("만료된 토큰이면 인증을 채우지 않는다")
    void 만료된토큰이면_인증을채우지않는다() throws Exception {
        long now = System.currentTimeMillis();
        assertRejectedSilently(bearer(signedToken("42", "ROLE_USER",
                new Date(now - 7_200_000L), new Date(now - 3_600_000L))));
    }

    @Test
    @DisplayName("서명이 유효해도 subject 가 소셜 ID 인 옛 형식 토큰이면 인증을 채우지 않는다")
    void 옛형식subject토큰이면_인증을채우지않는다() throws Exception {
        // 이 가드가 없으면 인증이 채워져 컨트롤러까지 흘러가고, 거기서 파싱에 실패해 400 이 되며
        // 실패한 subject 원문(소셜 ID)이 응답 본문에 실린다. (이슈 #5·#6)
        assertRejectedSilently(bearer(validPeriodToken("kakao_123", "ROLE_USER")));
    }

    @Test
    @DisplayName("role 클레임이 없는 토큰이면 인증을 채우지 않는다")
    void role이없는토큰이면_인증을채우지않는다() throws Exception {
        // 이 가드가 없으면 필터 안에서 new SimpleGrantedAuthority(null) 이 예외를 던지고,
        // 필터 예외는 @RestControllerAdvice 가 잡지 못해 컨테이너 500 이 된다.
        assertRejectedSilently(bearer(validPeriodToken("42", null)));
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 거절은 "조용해야" 한다 — 인증도 안 채우고, 응답 상태도 건드리지 않고, 체인은 계속 간다. */
    private void assertRejectedSilently(String authorizationHeader) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        if (authorizationHeader != null) {
            request.addHeader("Authorization", authorizationHeader);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, response, chain);

        assertThat(SecurityContextHolder.getContext().getAuthentication())
                .as("인증을 채우면 그대로 컨트롤러까지 흘러간다")
                .isNull();
        assertThat(chain.getRequest())
                .as("필터가 체인을 끊으면 permitAll 경로까지 함께 막힌다")
                .isNotNull();
        assertThat(response.getStatus())
                .as("401 은 SecurityConfig 의 진입점이 만든다 — 필터가 직접 만들면 인가 경계가 둘로 갈라진다")
                .isEqualTo(200);
    }

    private Authentication authenticate(String authorizationHeader) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.addHeader("Authorization", authorizationHeader);
        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());
        return SecurityContextHolder.getContext().getAuthentication();
    }

    private static String bearer(String token) {
        return "Bearer " + token;
    }

    private static JWTProvider newProvider() {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", SECRET);
        ReflectionTestUtils.setField(provider, "expirationMillis", 3_600_000L);
        ReflectionTestUtils.invokeMethod(provider, "init");
        return provider;
    }

    private static String validPeriodToken(String subject, String role) {
        long now = System.currentTimeMillis();
        return signedToken(subject, role, new Date(now), new Date(now + 3_600_000L));
    }

    /** createAccessToken 으로는 만들 수 없는 토큰(숫자가 아닌 sub, role 없음)을 직접 서명한다. */
    private static String signedToken(String subject, String role, Date issuedAt, Date expiration) {
        var builder = Jwts.builder()
                .setSubject(subject)
                .setIssuedAt(issuedAt)
                .setExpiration(expiration);
        if (role != null) {
            builder.claim("role", role);
        }
        return builder
                .signWith(Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8)), SignatureAlgorithm.HS256)
                .compact();
    }
}
