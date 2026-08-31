package com.heattrip.heat_trip_backend.OAuth.code;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.principal.UnauthenticatedException;
import com.heattrip.heat_trip_backend.OAuth.OAuthSecurityProperties;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.entity.RefreshToken;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 1회용 코드 → {@code AuthTokens}. (이슈 #14)
 *
 * <p>여기가 소셜 경로에서 토큰이 나가는 유일한 자리다. 그래서 <b>토큰의 subject 규약</b>
 * (이슈 #5 완료 조건 6·9)도 이제 이 클래스가 지킨다 — 예전에는 성공 핸들러가 토큰을
 * 만들었고 {@code OAuth2SuccessHandlerTest} 가 그 자리를 지켰다.
 */
class OAuthCodeExchangeServiceTest {

    /** 정확히 32바이트 — HS256 최소 키 길이. */
    private static final String SECRET = "test-only-secret-key-32bytes-min!!";

    private static final String PROVIDER_ID = "109876543210987654321";
    private static final long USER_ID = 42L;
    private static final Instant BASE = Instant.parse("2026-08-30T12:00:00Z");

    private AuthCodeStore codeStore;
    private OAuthCodeExchangeService service;
    private UserRepository userRepository;

    @BeforeEach
    void setUp() {
        OAuthSecurityProperties props = new OAuthSecurityProperties();
        props.setCodeTtlSeconds(60);
        codeStore = new AuthCodeStore(Clock.fixed(BASE, ZoneOffset.UTC), props);

        userRepository = mock(UserRepository.class);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(User.builder()
                .id(USER_ID)
                .provider("google")
                .socialId(PROVIDER_ID)
                .name("프로브 사용자")
                .nickname("프로브 사용자")
                .role("ROLE_USER")
                .build()));

        service = new OAuthCodeExchangeService(codeStore, jwtProvider(), refreshTokenService(), userRepository);
    }

    // ─────────────────── A. 정상 교환 ───────────────────

    @Test
    @DisplayName("코드를 토큰으로 바꾼다 — 액세스·refresh·expiresIn·isNew·user 가 전부 실린다")
    void 코드를_토큰으로_바꾼다() {
        String code = codeStore.issue(USER_ID, "google", "st-1", true);

        AuthTokensResponse tokens = service.exchange("google", code, "st-1");

        assertThat(tokens.accessToken()).isNotBlank();
        assertThat(tokens.refreshToken()).isNotBlank();
        assertThat(tokens.expiresIn()).isPositive();
        assertThat(tokens.isNew())
                .as("URL 쿼리로는 표현할 방법이 없던 값이다 — 소셜 신규 가입자의 온보딩 분기가 여기서 산다")
                .isTrue();
        assertThat(tokens.user()).isNotNull();
        assertThat(tokens.user().getId()).isEqualTo(USER_ID);
    }

    @Test
    @DisplayName("발급된 액세스 토큰의 subject 는 users.id 이고 소셜 ID 가 아니다")
    void 발급토큰의_subject가_usersId다() {
        // 예전에는 authentication.getName()(= "google_109876...")이 그대로 subject 였고,
        // 그 값이 소비처에서 이메일로 해석되어 모든 소셜 계정에서 /auth/me 가 400 이었다. (#5)
        String code = codeStore.issue(USER_ID, "google", "st-sub", false);

        Claims claims = parse(service.exchange("google", code, "st-sub").accessToken());

        assertThat(claims.getSubject()).isEqualTo("42");
        assertThat(claims.getSubject())
                .doesNotStartWith("google_")
                .doesNotStartWith("kakao_")
                .doesNotContain(PROVIDER_ID);
        assertThat(claims.get("role", String.class)).isEqualTo("ROLE_USER");
    }

    @Test
    @DisplayName("공급자 대소문자·공백은 가리지 않는다")
    void 공급자_표기흔들림은_통과시킨다() {
        String code = codeStore.issue(USER_ID, "google", "st-case", false);

        assertThat(service.exchange(" Google ", code, "st-case")).isNotNull();
    }

    // ─────────────────── B. 실패는 전부 401 ───────────────────

    @Test
    @DisplayName("같은 코드로 두 번 교환하면 두 번째는 401 이다 (완료 조건 2)")
    void 같은코드로_두번교환하면_두번째는_401이다() {
        String code = codeStore.issue(USER_ID, "google", "st-1", false);
        service.exchange("google", code, "st-1");

        assertThatThrownBy(() -> service.exchange("google", code, "st-1"))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("없는 코드는 401 이다")
    void 없는코드는_401이다() {
        assertThatThrownBy(() -> service.exchange("google", "not-a-real-code", "st-any"))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("코드를 만든 공급자와 다른 경로로 교환하면 401 이다")
    void 공급자가_다르면_401이다() {
        // 아니면 카카오로 얻은 코드를 /auth/oauth/google/callback 으로 밀어 넣어도 통과한다 —
        // 계약이 경로 변수를 두고 있는데 아무 의미가 없는 상태가 된다.
        String code = codeStore.issue(USER_ID, "kakao", "st-prov", false);

        assertThatThrownBy(() -> service.exchange("google", code, "st-prov"))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("state 가 코드 발급 시점의 값과 다르면 401 이다")
    void state가_다르면_401이다() {
        String code = codeStore.issue(USER_ID, "google", "st-1", false);

        assertThatThrownBy(() -> service.exchange("google", code, "st-2"))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("빈 state 로 발급된 코드는 교환되지 않는다 — 검사의 존재 여부를 클라이언트가 정하면 안 된다")
    void 빈state로_발급된_코드는_교환되지_않는다() {
        // 예전에는 "양쪽 다 빈 문자열이면 통과" 였다. 그 동작에서는 인증을 시작하는 쪽이
        // state 를 생략하기만 하면 서버쪽 두 번째 줄이 통째로 사라진다 — 검사를 켜고 끄는
        // 스위치를 클라이언트에게 준 것과 같다. 실측으로 빈 state 교환이 통과하는 것을
        // 확인했고(저장된 state='' , 통과 여부=true), 여기서 닫는다.
        String code = codeStore.issue(USER_ID, "google", "", false);

        assertThatThrownBy(() -> service.exchange("google", code, ""))
                .as("빈 state 를 통과시키면 그 클라이언트에 대해서는 응답 바꿔치기 방어가 0 이 된다")
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("빈 state 로 발급된 코드는 null 을 보내도 교환되지 않는다")
    void 빈state로_발급된_코드는_null로도_교환되지_않는다() {
        String code = codeStore.issue(USER_ID, "google", "", false);

        assertThatThrownBy(() -> service.exchange("google", code, null))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("실패한 교환도 코드를 죽인다 — 코드 하나에 시도 한 번이다")
    void 실패한_교환도_코드를_죽인다() {
        String code = codeStore.issue(USER_ID, "google", "st-1", false);

        assertThatThrownBy(() -> service.exchange("google", code, "wrong"))
                .isInstanceOf(UnauthenticatedException.class);
        // state 를 맞혀 다시 시도해도 이미 죽은 코드다. 이게 없으면 state 를 무한히 추측할 수 있다.
        assertThatThrownBy(() -> service.exchange("google", code, "st-1"))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("발급과 교환 사이에 사용자가 사라졌으면 401 이다")
    void 주체가_사라졌으면_401이다() {
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());
        // state 를 실어 발급한다 — 빈 state 로 두면 이 테스트가 '주체 소실' 이 아니라
        // 'state 부재' 때문에 초록이 되어 이름이 거짓말을 한다.
        String code = codeStore.issue(USER_ID, "google", "st-gone", false);

        assertThatThrownBy(() -> service.exchange("google", code, "st-gone"))
                .isInstanceOf(UnauthenticatedException.class);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static JWTProvider jwtProvider() {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", SECRET);
        ReflectionTestUtils.setField(provider, "expirationMillis", 3_600_000L);
        ReflectionTestUtils.invokeMethod(provider, "init");
        return provider;
    }

    private static RefreshTokenService refreshTokenService() {
        RefreshTokenRepository repository = mock(RefreshTokenRepository.class);
        when(repository.save(any(RefreshToken.class))).thenAnswer(i -> i.getArgument(0));
        return new RefreshTokenService(repository, mock(UserRepository.class), jwtProvider(),
                Clock.systemDefaultZone(), 1_209_600_000L);
    }

    private static Claims parse(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8)))
                .build()
                .parseClaimsJws(token)
                .getBody();
    }
}
