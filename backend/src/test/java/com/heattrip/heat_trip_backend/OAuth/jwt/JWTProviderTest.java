package com.heattrip.heat_trip_backend.OAuth.jwt;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.util.Date;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * JWTProvider 의 만료 시간이 설정(jwt.expiration)에서 오는지, 그리고 만료된 토큰이
 * 실제로 거부되는지를 잠그는 테스트. (이슈 #6)
 *
 * JWTProvider 는 @Value 필드 주입이라 순수 단위 테스트에서는 ReflectionTestUtils 로 값을
 * 넣고 init() 을 손으로 불러야 한다. 스프링 컨텍스트를 띄우는 검증은
 * JWTProviderSecretValidationTest 가 맡는다.
 */
class JWTProviderTest {

    /** 정확히 32바이트. HS256 최소 키 길이. src/test/resources/application-test.properties 와 같은 값. */
    private static final String SECRET = "test-only-secret-key-32bytes-min!!";

    private JWTProvider newProvider(long expirationMillis) {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", SECRET);
        ReflectionTestUtils.setField(provider, "expirationMillis", expirationMillis);
        ReflectionTestUtils.invokeMethod(provider, "init");
        return provider;
    }

    private Claims parse(String token) {
        Key key = Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8));
        return Jwts.parserBuilder().setSigningKey(key).build().parseClaimsJws(token).getBody();
    }

    /** exp - iat 을 초 단위로 계산한다. jjwt 는 두 값 모두 초 단위로 잘라 넣으므로 오차가 없다. */
    private long expiresInSeconds(String token) {
        Claims claims = parse(token);
        return (claims.getExpiration().getTime() - claims.getIssuedAt().getTime()) / 1000L;
    }

    @Test
    @DisplayName("jwt.expiration 이 3600000ms 이면 발급된 토큰의 exp - iat 은 3600초다.")
    void createAccessToken_1시간설정이면_만료가3600초다() {
        JWTProvider provider = newProvider(3_600_000L);

        String token = provider.createAccessToken(42L, "ROLE_USER");

        assertThat(expiresInSeconds(token)).isEqualTo(3600L);
    }

    @Test
    @DisplayName("getExpiresInSeconds() 는 설정된 만료 시간을 초로 환산해 돌려준다.")
    void getExpiresInSeconds_설정값을초로환산한다() {
        JWTProvider provider = newProvider(3_600_000L);

        assertThat(provider.getExpiresInSeconds()).isEqualTo(3600L);
    }

    @Test
    @DisplayName("jwt.expiration 을 1800000ms 로 바꾸면 토큰 만료와 getExpiresInSeconds() 가 모두 1800초로 따라간다.")
    void createAccessToken_설정을30분으로바꾸면_만료도30분이다() {
        JWTProvider provider = newProvider(1_800_000L);

        String token = provider.createAccessToken(42L, "ROLE_USER");

        assertThat(expiresInSeconds(token)).isEqualTo(1800L);
        assertThat(provider.getExpiresInSeconds()).isEqualTo(1800L);
    }

    @Test
    @DisplayName("발급된 토큰에서 사용자 ID 와 권한을 다시 읽어올 수 있고 유효성 검사를 통과한다.")
    void createAccessToken_발급한토큰은_파싱과검증을통과한다() {
        JWTProvider provider = newProvider(3_600_000L);

        String token = provider.createAccessToken(42L, "ROLE_USER");

        assertThat(provider.validateToken(token)).isTrue();
        assertThat(provider.getUserIdFromToken(token)).isEqualTo("42");
        assertThat(provider.getRoleFromToken(token)).isEqualTo("ROLE_USER");
    }

    @Test
    @DisplayName("발급된 토큰의 subject 는 users.id 를 그대로 옮긴 숫자 문자열이다.")
    void createAccessToken_subject가_숫자문자열이다() {
        JWTProvider provider = newProvider(3_600_000L);

        String token = provider.createAccessToken(42L, "ROLE_USER");

        assertThat(parse(token).getSubject())
                .as("계약(openapi.yaml)상 sub 는 불투명 키지만, 서버 내부 규약은 users.id 다 (이슈 #5)")
                .isEqualTo("42")
                .matches("\\d+");
    }

    @Test
    @DisplayName("subject 로 쓸 users.id 가 없으면 토큰을 만들지 않고 예외를 던진다.")
    void createAccessToken_userId가null이면_예외다() {
        JWTProvider provider = newProvider(3_600_000L);

        assertThatThrownBy(() -> provider.createAccessToken(null, "ROLE_USER"))
                .as("sub=\"null\" 토큰이 발급되면 그 계정은 재로그인 전까지 영구 401 이 된다")
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("서명이 유효해도 subject 가 이메일이거나 소셜 ID 인 옛 형식 토큰은 검증을 통과하지 못한다.")
    void validateToken_subject가_숫자가아니면_false다() {
        JWTProvider provider = newProvider(3_600_000L);

        for (String legacySubject : new String[] { "a@b.com", "kakao_123", "google_109876543210987654321", "" }) {
            assertThat(provider.validateToken(signedToken(legacySubject, "ROLE_USER")))
                    .as("옛 형식 subject(%s)를 필터가 통과시키면 컨트롤러에서 파싱에 실패해 400 이 되고 "
                            + "그 원문이 응답 본문에 실린다", legacySubject)
                    .isFalse();
        }
    }

    @Test
    @DisplayName("subject 가 0 이하의 숫자인 토큰도 검증을 통과하지 못한다.")
    void validateToken_subject가_양수가아니면_false다() {
        JWTProvider provider = newProvider(3_600_000L);

        assertThat(provider.validateToken(signedToken("0", "ROLE_USER"))).isFalse();
        assertThat(provider.validateToken(signedToken("-7", "ROLE_USER"))).isFalse();
    }

    @Test
    @DisplayName("role 클레임이 없거나 비어 있는 토큰은 검증을 통과하지 못한다.")
    void validateToken_role이없으면_false다() {
        JWTProvider provider = newProvider(3_600_000L);

        // 필터 안에서 new SimpleGrantedAuthority(null) 이 터지면 @RestControllerAdvice 가 잡지 못해
        // 컨테이너 500 이 된다. 완료 조건("어떤 입력에서도 401")을 지키려면 여기서 막아야 한다.
        assertThat(provider.validateToken(signedToken("42", null))).isFalse();
        assertThat(provider.validateToken(signedToken("42", "   "))).isFalse();
    }


    @Test
    @DisplayName("이미 만료된 토큰은 validateToken 이 false 를 돌려주고 getUserIdFromToken 은 예외를 던진다.")
    void validateToken_만료된토큰이면_false를돌려준다() {
        JWTProvider provider = newProvider(3_600_000L);
        String expired = signedToken(
                new Date(System.currentTimeMillis() - 7_200_000L),  // iat: 2시간 전
                new Date(System.currentTimeMillis() - 3_600_000L)); // exp: 1시간 전

        assertThat(provider.validateToken(expired)).isFalse();
        assertThatThrownBy(() -> provider.getUserIdFromToken(expired))
                .isInstanceOf(JWTProvider.InvalidTokenException.class)
                .hasMessage("Invalid JWT token");
    }

    @Test
    @DisplayName("만료·위조·형식 오류가 모두 같은 메시지 하나로 뭉개진다는 현재 한계를 고정한다.")
    void parseClaims_만료와위조와형식오류를_같은메시지로뭉갠다() {
        JWTProvider provider = newProvider(3_600_000L);

        String expired = signedToken(
                new Date(System.currentTimeMillis() - 7_200_000L),
                new Date(System.currentTimeMillis() - 3_600_000L));
        // 다른 키로 서명한 토큰 = 위조
        String forged = Jwts.builder()
                .setSubject("user-1")
                .claim("role", "ROLE_USER")
                .setIssuedAt(new Date())
                .setExpiration(new Date(System.currentTimeMillis() + 3_600_000L))
                .signWith(Keys.hmacShaKeyFor("another-secret-key-32bytes-long!!".getBytes(StandardCharsets.UTF_8)),
                        SignatureAlgorithm.HS256)
                .compact();
        String malformed = "not-a-jwt";

        // 호출부는 셋을 구분할 수 없다 — 401(만료)과 403(위조)을 나눠 주려면 예외를 쪼개야 한다.
        for (String bad : new String[] { expired, forged, malformed }) {
            assertThat(provider.validateToken(bad)).isFalse();
            assertThatThrownBy(() -> provider.getUserIdFromToken(bad))
                    .isInstanceOf(JWTProvider.InvalidTokenException.class)
                    .hasMessage("Invalid JWT token");
        }
    }

    private String signedToken(Date issuedAt, Date expiration) {
        return signedToken("42", "ROLE_USER", issuedAt, expiration);
    }

    /**
     * 임의의 subject·role 로 유효 서명·미만료 토큰을 만든다.
     *
     * <p>{@code createAccessToken} 을 쓰지 않는 이유: 그 시그니처가 {@code Long} 이라 "숫자가 아닌
     * subject" 나 "role 이 없는 토큰"을 아예 표현할 수 없다. 여기서 검증하려는 것은 <b>이미 발급되어
     * 사용자 손에 있는</b> 그런 토큰을 만났을 때의 동작이다.
     */
    private String signedToken(String subject, String role) {
        long now = System.currentTimeMillis();
        return signedToken(subject, role, new Date(now), new Date(now + 3_600_000L));
    }

    private String signedToken(String subject, String role, Date issuedAt, Date expiration) {
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
