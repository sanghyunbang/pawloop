package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.user.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.entity.RefreshToken;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.Base64;
import java.util.HexFormat;

/**
 * Refresh Token 의 유일한 출입구. (이슈 #9)
 *
 * <p>토큰 생성·해싱·만료 계산·회전·폐기·정리를 여기서만 안다. 호출부
 * ({@code UserService}·{@code AuthController}·{@code OAuth2SuccessHandler})는 리포지토리를
 * 직접 만지지 않는다. 나중에 Redis 캐시를 끼운다면 그 이음새가 이 경계다 — 구현체가 하나뿐인
 * 포트 인터페이스를 미리 만들지 않은 이유는 소비자 없는 {@code jti} 를 미리 박지 않는 것과 같다.
 *
 * <h2>토큰의 형태</h2>
 * {@link SecureRandom} 32바이트(256bit)를 <b>패딩 없는</b> Base64URL 로 인코딩한 43자
 * 불투명 문자열이다. JWT 가 아닌 이유는 폐기할 수 있어야 하기 때문이고, 패딩을 뺀 이유는
 * 이 값이 딥링크 쿼리스트링에 실리기 때문이다 — Base64URL 알파벳
 * ({@code A-Z a-z 0-9 - _})은 URL 에 그대로 써도 되지만 {@code =} 는 인코딩이 필요하다.
 *
 * <h2>회전과 재사용 감지</h2>
 * 검사 순서가 곧 계약이다: ①없음 ②만료 ③재사용. <b>만료를 먼저 보는 것이 중요하다</b> —
 * 순서를 바꾸면 "만료된 데다 폐기된" 토큰이 전량 폐기를 유발한다. 만료는 유출의 증거가 아니라
 * 시간의 경과다(완료 조건 5).
 *
 * <p>이미 폐기된 RT 가 다시 왔다는 것은 두 주체가 같은 RT 를 갖고 있었다는 뜻인데, 서버는
 * 어느 쪽이 정당한 소유자인지 가릴 정보가 없다. 체인 단위로만 끊으면 탈취자가 먼저 회전한
 * 경우 <b>탈취자의 새 RT 가 살아남는다</b> — 막으려던 것을 정확히 못 막는다. RT 는 소지
 * 자격증명이고 오판의 대가가 계정 전체이므로 닫는 쪽으로 실패한다: 그 사용자의 살아 있는 RT
 * 전량 폐기(완료 조건 4).
 *
 * <h2>트랜잭션을 씌우지 않는다</h2>
 * {@link #rotate(String)} 에 {@code @Transactional} 이 <b>없는 것은 의도다.</b> 재사용 감지는
 * "전량 폐기 후 401"인데, 하나의 트랜잭션 안이면 던지는 순간 그 폐기가 함께 롤백되어
 * 완료 조건 4 가 조용히 거짓이 된다. 대신 수정 쿼리 각각이
 * {@code RefreshTokenRepository} 에서 자기 트랜잭션을 갖는다.
 */
@Service
public class RefreshTokenService {

    private static final Logger log = LoggerFactory.getLogger(RefreshTokenService.class);

    /**
     * 256bit. 무차별 대입이 성립하지 않는 크기다 — 토큰을 맞히려는 공격은 이 경로로 성립하지 않는다.
     *
     * <p><b>다만 {@code POST /auth/token/refresh} 는 현재 rate limit 이 전혀 없는 상태로 열려 있다.</b>
     * {@code ApiRateLimitFilter} 는 경로를 하나씩 열거하는데 이 경로가 그 목록에 없고, 동시에
     * {@code SecurityConfig.publicMatchers} 에 있어 인증 없이 도달한다. 남는 위험은 무차별 대입이
     * 아니라 비용 비대칭이다 — 인증 없이 누구나 요청 1건당 SHA-256 1회 + 인덱스 조회 1회를
     * 강제할 수 있고, 앱이 토큰 만료마다 자동으로 때리는 경로라 오작동하는 클라이언트 한 대가
     * 그대로 트래픽이 된다({@code /auth/login} 은 10회/분으로 묶여 있다).
     *
     * <p>여기서 닫지 않은 이유: 버킷 하나를 더하는 것은 {@code PublicSecurityProperties}·
     * {@code application.properties}·{@code .env.example} 을 함께 건드리는 일이고, 임계값을 잘못
     * 잡으면 정상 클라이언트가 갱신에 실패해 로그아웃된다. rate limit 정책의 소유자는 #14 다 —
     * <b>이 경로가 이미 무제한으로 열려 있다는 사실을 그쪽에 넘긴다.</b>
     */
    private static final int TOKEN_BYTES = 32;

    private final RefreshTokenRepository refreshTokenRepository;
    private final UserRepository userRepository;
    private final AccessTokenIssuer accessTokenIssuer;
    private final Clock clock;
    private final long refreshExpirationMillis;

    private final SecureRandom secureRandom = new SecureRandom();
    private final Base64.Encoder base64Url = Base64.getUrlEncoder().withoutPadding();

    public RefreshTokenService(RefreshTokenRepository refreshTokenRepository,
                               UserRepository userRepository,
                               AccessTokenIssuer accessTokenIssuer,
                               Clock clock,
                               @Value("${jwt.refresh-expiration}") long refreshExpirationMillis) {
        if (refreshExpirationMillis <= 0) {
            throw new IllegalStateException("jwt.refresh-expiration 은 0보다 큰 밀리초 값이어야 합니다.");
        }
        this.refreshTokenRepository = refreshTokenRepository;
        this.userRepository = userRepository;
        this.accessTokenIssuer = accessTokenIssuer;
        this.clock = clock;
        this.refreshExpirationMillis = refreshExpirationMillis;
    }

    /**
     * 새 RT 를 발급해 원장에 <b>해시로</b> 저장하고 원문을 돌려준다.
     *
     * <p>돌려준 원문은 호출부가 응답이나 딥링크로 내보내는 것 말고 다른 데 쓰면 안 된다.
     * 로그·예외 메시지에 남기지 않는다 — 14일짜리 자격증명이라 유출의 대가가 AT 보다 크다(#6).
     *
     * @return RT 원문(패딩 없는 Base64URL 43자)
     */
    public String issueFor(Long userId) {
        if (userId == null) {
            throw new IllegalArgumentException("refresh 토큰의 주체(users.id)가 없습니다.");
        }
        String raw = newRawToken();
        LocalDateTime now = LocalDateTime.now(clock);

        refreshTokenRepository.save(RefreshToken.builder()
                .userId(userId)
                .tokenHash(sha256Hex(raw))
                .expiresAt(now.plus(Duration.ofMillis(refreshExpirationMillis)))
                .createdAt(now)
                .build());

        // 원문도 해시도 남기지 않는다. 발급이 일어났다는 사실만 남긴다. (#6)
        log.debug("refresh 토큰 발급");
        return raw;
    }

    /**
     * RT 를 회전한다 — 옛 행을 폐기하고 새 AT·새 RT 를 발급한다.
     *
     * @param rawToken 클라이언트가 보낸 RT 원문
     * @return 새 액세스 토큰 · 새 refresh 토큰 · 액세스 토큰 만료 초
     * @throws UnauthenticatedException 없음·만료·재사용·주체 소실 — 전부 <b>본문 없는 401</b> 이다.
     *         새 예외 타입도 새 {@code @ControllerAdvice} 도 만들지 않는다. 별도 advice 로 빼면
     *         예외 구체성이 아니라 빈 순서로 승자가 정해져 catch-all 이 먼저 잡아 500 이 샌다(#44).
     */
    public AuthTokensResponse rotate(String rawToken) {
        if (rawToken == null || rawToken.isBlank()) {
            throw new UnauthenticatedException();
        }

        // ① 없음
        RefreshToken stored = refreshTokenRepository.findByTokenHash(sha256Hex(rawToken))
                .orElseThrow(UnauthenticatedException::new);

        LocalDateTime now = LocalDateTime.now(clock);

        // ② 만료 — 전량 폐기하지 않는다. 시간이 지난 것은 유출의 증거가 아니다.
        if (!stored.getExpiresAt().isAfter(now)) {
            throw new UnauthenticatedException();
        }

        // ③ 재사용 — 조건부 UPDATE 의 영향 행 수가 그대로 판정이다.
        //    0 은 '이미 폐기됨' 과 '같은 RT 를 동시에 보낸 다른 요청에 짐' 을 함께 뜻하는데,
        //    서버는 둘을 구별할 수 없고 대응도 같다.
        if (refreshTokenRepository.revokeIfLive(stored.getId(), now) == 0) {
            refreshTokenRepository.revokeAllByUserId(stored.getUserId(), now);
            // 문구가 사건을 단정하지 않는 이유: 이 분기는 '회전으로 폐기된 옛 RT 재사용'(진짜
            // 유출 신호)과 '로그아웃으로 폐기된 RT 로 앱이 무심코 갱신을 시도'(아주 흔한 일)를
            // 함께 탄다. 서버는 둘을 구별할 수단이 없다. "유출됐다"고 적으면 로그 기반 알림에
            // 오탐이 상시로 뜨고, 그러면 진짜 신호가 그 소음에 묻힌다.
            log.warn("살아 있지 않은 refresh 토큰이 제시되어 해당 사용자의 세션을 전량 폐기했다 "
                    + "— 회전 재사용 또는 로그아웃 이후 재시도.");
            throw new UnauthenticatedException();
        }

        // role 을 읽어야 AT 를 만들 수 있다. 탈퇴한 사용자는 ① 에서 이미 걸린다
        // (deleteMe 가 RT 행을 먼저 지운다) — 그래도 경합을 대비해 401 로 닫는다.
        User user = userRepository.findById(stored.getUserId())
                .orElseThrow(UnauthenticatedException::new);

        return new AuthTokensResponse(
                accessTokenIssuer.createAccessToken(user.getId(), roleOf(user)),
                issueFor(user.getId()),
                accessTokenIssuer.getExpiresInSeconds());
    }

    /**
     * 그 사용자의 살아 있는 RT 를 전부 폐기한다 — 전 기기 로그아웃.
     *
     * <p>행을 지우지 않고 {@code revoked_at} 을 찍는다. 지우면 폐기된 RT 가 다시 왔을 때
     * "없는 토큰"과 구별되지 않아 재사용 감지가 무력해진다.
     */
    public int revokeAllByUserId(Long userId) {
        return refreshTokenRepository.revokeAllByUserId(userId, LocalDateTime.now(clock));
    }

    /** 탈퇴 정리. 폐기가 아니라 삭제다 (완료 조건 7). */
    public int deleteAllByUserId(Long userId) {
        return refreshTokenRepository.deleteByUserId(userId);
    }

    /**
     * 만료된 행을 지운다. 폐기 여부는 보지 않는다 — 만료된 토큰은 어차피 401 이고
     * 전량 폐기를 유발하지 않기로 이미 정했으므로 재사용 감지가 약해지지 않는다.
     *
     * <p>조회 시 lazy 삭제를 고르지 않은 이유: 그 방식은 <b>다시 오지 않는 사용자의 행</b>을
     * 영원히 못 지운다. 정확히 쌓이는 것이 그 행들이다.
     */
    public int purgeExpired() {
        int removed = refreshTokenRepository.deleteByExpiresAtBefore(LocalDateTime.now(clock));
        log.info("만료된 refresh 토큰 {}건을 정리했다.", removed);
        return removed;
    }

    // ─────────────────────────── helpers ───────────────────────────

    private String newRawToken() {
        byte[] bytes = new byte[TOKEN_BYTES];
        secureRandom.nextBytes(bytes);
        return base64Url.encodeToString(bytes);
    }

    /**
     * 결정적 해시. 인덱스 조회가 성립해야 하므로 솔트를 쓰지 않는다.
     *
     * <p>pepper(HMAC)도 두지 않았다. DB 만 유출된 상황에서 256bit 균일 난수의 SHA-256 은
     * 역산할 방법이 없으므로 pepper 가 막아 주는 것이 없고, 대신 시크릿 로테이션이 전 세션을
     * 죽이는 결합만 생긴다.
     */
    static String sha256Hex(String raw) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(raw.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            // SHA-256 은 모든 JVM 이 반드시 제공한다(JLS 보장). 여기 오면 런타임이 망가진 것이다.
            throw new IllegalStateException("SHA-256 을 사용할 수 없습니다.", e);
        }
    }

    /** role 컬럼이 없던 시절에 만들어진 행은 값이 비어 있을 수 있다. */
    private static String roleOf(User user) {
        String role = user.getRole();
        return (role == null || role.isBlank()) ? User.ROLE_USER : role;
    }
}
