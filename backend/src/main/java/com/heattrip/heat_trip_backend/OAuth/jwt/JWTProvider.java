package com.heattrip.heat_trip_backend.OAuth.jwt;

import io.jsonwebtoken.*; // JWT 토큰 생성을 위한 JJWT 라이브러리의 핵심 클래스들
import io.jsonwebtoken.security.Keys; // 안전한 서명 키 생성을 위한 도구

import jakarta.annotation.PostConstruct;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.util.Date;

@Component
public class JWTProvider {

    private static final Logger log = LoggerFactory.getLogger(JWTProvider.class);

    /**
     * HS256 서명 키의 최소 길이(바이트).
     * RFC 7518 §3.2 — HMAC 키는 해시 출력 길이(SHA-256 → 32바이트) 이상이어야 한다.
     * jjwt 의 {@link Keys#hmacShaKeyFor(byte[])} 도 이보다 짧으면 예외를 던지지만,
     * 그 시점은 "토큰을 처음 만들 때"가 아니라 "빈 초기화 시점"이어야 운영 중 발견을 막는다.
     */
    public static final int MIN_SECRET_BYTES = 32;

    // application-{profile}.properties 파일에서 jwt.secret 값을 읽기
    @Value("${jwt.secret}")
    private String secret;

    /**
     * 액세스 토큰 유효 시간(밀리초). application-{profile}.properties 의 jwt.expiration.
     * 예전에는 이 값이 코드에 `1000L * 60 * 60 * 10000`(약 417일)로 하드코딩돼 있었고
     * 설정 파일의 jwt.expiration 은 아무도 읽지 않았다. (이슈 #6)
     */
    @Value("${jwt.expiration}")
    private long expirationMillis;

    // JWT 서명을 위한 키 객체
    // 이 키는 비밀 키로, JWT 토큰의 서명을 생성하고 검증하는 데 사용됩니다.
    private Key key;

    // @PostConstruct 어노테이션은 이 메서드가 빈 초기화 후에 호출됨을 나타냅니다.
    // 이 메서드는 JWTProvider가 생성된 후, 즉 의존성 주입이 완료된 후에 실행됩니다.
    // 이 시점에서 비밀 키를 검증하고, 실제 서명용 키 객체를 생성합니다.
    @PostConstruct
    protected void init() {
        // 시크릿이 비었거나 짧으면 "부팅 시점에" 죽는다.
        // 예외 메시지에는 최소 요구 길이만 남긴다 — 실제 시크릿이나 그 길이는 절대 남기지 않는다.
        if (secret == null || secret.isBlank()) {
            throw new IllegalStateException(
                    "jwt.secret 이 설정되지 않았습니다. HS256 서명 키는 최소 " + MIN_SECRET_BYTES + "바이트여야 합니다.");
        }
        if (secret.getBytes(StandardCharsets.UTF_8).length < MIN_SECRET_BYTES) {
            throw new IllegalStateException(
                    "jwt.secret 이 너무 짧습니다. HS256 서명 키는 최소 " + MIN_SECRET_BYTES + "바이트여야 합니다.");
        }
        if (expirationMillis <= 0) {
            throw new IllegalStateException("jwt.expiration 은 0보다 큰 밀리초 값이어야 합니다.");
        }

        // 검증된 비밀 키를 기반으로 실제 서명용 key 객체 생성
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 액세스 토큰의 유효 시간(초).
     * API 계약(docs/04-api/openapi.yaml)의 AuthTokens.expiresIn 에 그대로 실어 보낼 값이다.
     * @return 만료까지 남는 초 (예: 3600)
     */
    public long getExpiresInSeconds() {
        return expirationMillis / 1000L;
    }

    /**
     * JWT Access Token 생성.
     *
     * <p><b>subject 는 {@code users.id} 다.</b> 파라미터 타입이 {@code Long} 인 것이 이 규약의 방어선이다 —
     * 예전에는 {@code String} 이라 이메일({@code UserService.login})과 소셜 ID
     * ({@code OAuth2SuccessHandler} 의 {@code authentication.getName()})가 아무 저항 없이 들어왔고,
     * 그래서 토큰 하나로 세 가지 subject 규약이 공존했다. 이제 그 둘은 컴파일되지 않는다. (이슈 #5)
     *
     * <p>클레임은 {@code sub}·{@code role}·{@code iat}·{@code exp} 넷뿐이다.
     * {@code jti}·{@code prv} 는 계약(docs/04-api/openapi.yaml)이 이슈 #9 를 소유자로 지정해 두었다.
     *
     * @param userId users 테이블 PK. null 이면 {@link IllegalArgumentException}
     * @param role 사용자 권한 정보 (예: "ROLE_USER")
     * @return 생성된 JWT 문자열
     */
    public String createAccessToken(Long userId, String role) {
        if (userId == null) {
            // 토큰을 만들 수 없는 상태다. sub="null" 토큰을 발급하면 그 계정은 재로그인 전까지 영구 401 이 된다.
            throw new IllegalArgumentException("액세스 토큰의 subject(users.id)가 없습니다.");
        }

        Date now = new Date();
        Date expiry = new Date(now.getTime() + expirationMillis);

        // 토큰 원문·시크릿·시크릿 길이·사용자 식별자는 어떤 로그 레벨에도 남기지 않는다. (이슈 #6)
        log.debug("액세스 토큰 발급 (만료 {}초)", getExpiresInSeconds());

        return Jwts.builder()
                .setSubject(String.valueOf(userId))
                .claim("role", role)
                .setIssuedAt(now)
                .setExpiration(expiry)
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();
    }

    public String getUserIdFromToken(String token) {
        return parseClaims(token).getSubject();
    }

    public String getRoleFromToken(String token) {
        return roleOf(parseClaims(token));
    }

    /**
     * {@code role} 클레임을 문자열로 읽는다. 값이 없거나 문자열이 아니면 null.
     *
     * <p>{@code Claims.get("role", String.class)} 를 그대로 쓰지 않는 이유: 타입이 다르면 jjwt 가
     * {@code RequiredTypeException} 을 던지는데, 그 예외는 {@code parseClaims} 의 try 밖에서 나므로
     * {@code JWTAuthenticationFilter} 를 뚫고 나가 컨테이너 500 이 된다.
     */
    private static String roleOf(Claims claims) {
        Object role = claims.get("role");
        return (role instanceof String value) ? value : null;
    }

    /**
     * subject 를 {@code users.id} 로 해석한다.
     *
     * <p>실패해도 <b>값을 로그에 넣지 않는다</b> — 옛 형식 토큰의 subject 는 이메일이거나
     * 소셜 ID({@code kakao_1234567890})다. (이슈 #6)
     *
     * @throws InvalidTokenException subject 가 양의 long 이 아닐 때. 새 예외 타입을 만들지 않는 이유는
     *         호출부(필터)가 이것을 서명 실패·만료와 <b>똑같이</b> 다뤄야 하기 때문이다.
     */
    private static long requireNumericSubject(Claims claims) {
        try {
            long userId = Long.parseLong(claims.getSubject());
            if (userId <= 0) {
                throw new InvalidTokenException("Invalid JWT token");
            }
            return userId;
        } catch (NumberFormatException e) {
            log.debug("JWT subject 가 users.id 형식이 아니다 (옛 형식 토큰으로 보인다)");
            throw new InvalidTokenException("Invalid JWT token");
        }
    }

    /**
     * JWT 토큰을 파싱해서 내부 클레임(내용)을 추출
     * @param token JWT 토큰 문자열
     * @return Claims 객체 (토큰의 내용)
     * @throws InvalidTokenException 만료·위조·형식 오류 등 어떤 이유로든 파싱에 실패했을 때
     */
    private Claims parseClaims(String token) {
        try {
            return Jwts.parserBuilder() // 파서를 설정할 빌더 객체를 가져옴
                    .setSigningKey(key) // 서명 검증에 쓸 키를 설정
                    .build() // 파서 빌드 완료(객체가 생성된 걸 의미)
                    .parseClaimsJws(token) // JWT 문자열을 실제로 파싱하고 서명 확인
                    .getBody(); // 성공적으로 파싱되면 내부 payload(클레임) 반환
        } catch (JwtException | IllegalArgumentException e) {
            // 유효하지 않은 토큰(만료, 위조, 형식 오류 등)이 들어오면 발생.
            //
            // 알려진 한계: 세 원인을 하나의 메시지로 뭉갠다. 호출부가 "만료"와 "위조"를
            // 구분해 401/403 을 나눠 주려면 예외 타입을 쪼개야 한다 — 계약 정리(#5)와 함께 다룬다.
            //
            // 원인 예외를 cause 로 달지 않는 이유: jjwt 의 메시지에 토큰 조각이 섞여 들어올 수
            // 있고, 그게 상위 예외 핸들러의 스택트레이스 로그에 그대로 실린다. 대신 원인
            // "타입 이름"만 debug 로 남긴다.
            log.debug("JWT 파싱 실패: {}", e.getClass().getSimpleName());
            throw new InvalidTokenException("Invalid JWT token");
        }
    }

    /**
     * 이 토큰으로 인증을 채워도 되는가.
     *
     * <p>세 가지를 함께 본다. <b>서명·만료 파싱 성공</b> · <b>{@code sub} 가 양의 long</b> ·
     * <b>{@code role} 이 비어 있지 않음</b>.
     *
     * <p>뒤의 두 조건이 여기 있는 이유는 완료 조건("어떤 입력에서도 500 이 아니라 401")이다. (이슈 #5)
     * <ul>
     *   <li>수치 subject 를 여기서 막지 않으면 옛 형식 토큰이 컨트롤러까지 흘러가 거기서
     *       파싱에 실패한다 — 응답은 400 이고 본문에 실패한 subject 원문(이메일/소셜 ID)이 실린다.</li>
     *   <li>role 을 막지 않으면 필터 안에서 {@code new SimpleGrantedAuthority(null)} 이 예외를 던지는데,
     *       필터 예외는 {@code @RestControllerAdvice} 가 잡지 못해 컨테이너 500 이 된다.</li>
     * </ul>
     * 여기서 false 를 돌려주면 필터가 {@code SecurityContext} 를 채우지 않고 통과시키고,
     * {@code SecurityConfig} 의 {@code HttpStatusEntryPoint(UNAUTHORIZED)} 가 본문 없는 401 을 만든다.
     */
    public boolean validateToken(String token) {
        try {
            Claims claims = parseClaims(token); // 내부에서 예외 없으면 서명·만료는 통과
            requireNumericSubject(claims);
            String role = roleOf(claims);
            return role != null && !role.isBlank();
        } catch (InvalidTokenException e) {
            // 예전에는 여기서 JwtException 을 잡았는데, parseClaims 는 이미 RuntimeException 으로
            // 감싼 뒤였다. 그래서 만료 토큰이 들어오면 false 가 아니라 예외가 그대로 튀어나갔다. (이슈 #6)
            return false; // 파싱 실패하면 유효하지 않은 토큰
        }
    }

    /**
     * 토큰 파싱 실패를 나타내는 예외.
     * 메시지는 기존 동작("Invalid JWT token")을 그대로 유지한다 — 호출부가 문자열에 의존할 수 있어서다.
     */
    public static class InvalidTokenException extends RuntimeException {
        public InvalidTokenException(String message) {
            super(message);
        }
    }
}
