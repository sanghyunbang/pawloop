package com.heattrip.heat_trip_backend.OAuth.code;

import com.heattrip.heat_trip_backend.OAuth.OAuthSecurityProperties;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 1회용 인가 코드의 발급소이자 유일한 소비처. (이슈 #14)
 *
 * <h2>왜 코드인가</h2>
 * 예전에는 성공 딥링크가 {@code heattrip://login-callback?token=<AT>&refresh=<RT>} 였다.
 * 커스텀 스킴은 <b>어느 앱이든 등록할 수 있고</b>, URL 은 302 의 {@code Location} 헤더와
 * 브라우저 히스토리에 남는다. 즉 14일짜리 자격증명이 가로채기 쉬운 채널로 나가고 있었다.
 * 대신 <b>60초 살고 한 번 쓰면 죽는 난수</b>를 내보내면, 가로채도 쓸 수 있는 창이 거의 없다.
 *
 * <h2>왜 인메모리인가 — 그리고 수평 확장 시 무엇이 깨지는가</h2>
 * DB 테이블을 하나 더 만들지 않았다. 근거는 셋이다.
 * <ul>
 *   <li><b>수명이 60초다.</b> 재기동 사이에 살아남아야 할 이유가 없다. 재기동 중에 진행 중이던
 *       로그인은 실패하고, 사용자는 버튼을 한 번 더 누른다 — RT 를 잃는 것과 비교할 수 없다.</li>
 *   <li><b>쓰기가 잦고 읽기는 한 번뿐이다.</b> 로그인마다 INSERT 1 + SELECT 1 + DELETE 1 이
 *       늘어나는데, 그 행은 60초 뒤에 전부 쓰레기다. 정리 잡이 하나 더 생긴다.</li>
 *   <li><b>지금 서버는 단일 인스턴스다.</b> docker-compose 에 app 컨테이너가 하나다.</li>
 * </ul>
 *
 * <p><b>⚠️ 수평 확장하는 순간 무엇이 깨지는가:</b> 코드를 발급한 인스턴스와 교환 요청을 받는
 * 인스턴스가 다르면 {@link #consume(String)} 이 빈 값을 돌려주고 <b>정상 로그인이 401 이 된다.</b>
 * 딥링크 복귀는 새 TCP 연결이라 로드밸런서가 같은 인스턴스로 보낸다는 보장이 없다. 즉 인스턴스를
 * 2대로 늘리는 순간 소셜 로그인이 절반쯤 실패하기 시작하고, 그 증상은 "가끔 로그인이 안 된다"로
 * 보고된다. 그때 할 일은 스티키 세션이 아니라 <b>이 맵을 공유 저장소(Redis 등)로 옮기는 것</b>이다.
 * 스티키 세션은 인스턴스가 하나 죽는 순간 같은 증상을 되돌려 놓는다.
 *
 * <p>같은 이유로 Spring Security 의 {@code HttpSessionOAuth2AuthorizationRequestRepository}
 * (기본값)도 이미 세션에 의존한다 — 이 클래스가 새로 만든 제약이 아니라, 이미 있던 제약과
 * 같은 줄에 서는 것이다.
 */
@Component
public class AuthCodeStore {

    private static final Logger log = LoggerFactory.getLogger(AuthCodeStore.class);

    /** 256bit. 60초 안에 맞힐 수 있는 크기가 아니다 — rate limit 은 그 위의 두 번째 벽이다. */
    private static final int CODE_BYTES = 32;

    /** 코드 원문 → 코드가 붙들고 있는 사실. <b>이 맵에 토큰은 없다.</b> */
    private final Map<String, AuthCode> codes = new ConcurrentHashMap<>();

    private final SecureRandom secureRandom = new SecureRandom();
    private final Base64.Encoder base64Url = Base64.getUrlEncoder().withoutPadding();

    private final Clock clock;
    private final OAuthSecurityProperties properties;

    public AuthCodeStore(Clock clock, OAuthSecurityProperties properties) {
        this.clock = clock;
        this.properties = properties;
    }

    /**
     * 코드를 발급한다. 돌아온 문자열은 딥링크 쿼리에 그대로 실린다.
     *
     * <p>패딩 없는 Base64URL 이라 URL 인코딩이 필요 없다 — {@code =} 가 붙으면 앱쪽 파서마다
     * 다르게 다뤄질 여지가 생긴다.
     *
     * @return 코드 원문(43자)
     */
    public String issue(Long userId, String provider, String state, boolean isNew) {
        if (userId == null) {
            throw new IllegalArgumentException("1회용 코드의 주체(users.id)가 없습니다.");
        }
        purgeExpired();

        byte[] bytes = new byte[CODE_BYTES];
        secureRandom.nextBytes(bytes);
        String code = base64Url.encodeToString(bytes);

        Instant expiresAt = clock.instant().plus(Duration.ofSeconds(ttlSeconds()));
        codes.put(code, new AuthCode(userId, provider, state, isNew, expiresAt));

        // 코드 원문도, users.id 도, state 도 남기지 않는다. 발급이 일어났다는 사실만. (이슈 #6)
        log.debug("소셜 로그인 1회용 코드 발급");
        return code;
    }

    /**
     * 코드를 소비한다. <b>성공하든 실패하든 그 코드는 이후 다시 쓸 수 없다.</b>
     *
     * <p>두 개의 벽이 있고 <b>서로 독립이다</b> — 하나를 지워도 나머지 하나는 그대로 선다
     * (이슈 #14 완료 조건 10). 순서를 이렇게 둔 이유:
     * <ol>
     *   <li><b>1회성.</b> {@code remove} 가 곧 "사용 표시"다. 원자적이라 같은 코드로 동시에
     *       두 요청이 와도 한쪽만 값을 받는다. {@code get} 으로 바꾸면 코드가 영구 재사용
     *       가능해지고 {@code 같은코드로_두번교환하면_두번째는_실패한다} 가 죽는다.</li>
     *   <li><b>만료.</b> 만료된 코드도 위에서 이미 지워졌다 — "만료됐으니 살려 둔다" 는 없다.
     *       이 검사를 지우면 {@code 발급후_61초가_지나면_교환이_실패한다} 가 죽는다.</li>
     * </ol>
     *
     * @return 살아 있는 코드였으면 그 내용, 아니면 빈 값. <b>실패 사유를 구분해 돌려주지 않는다</b> —
     *         호출부가 그것으로 다른 응답을 주면 코드의 존재 여부를 알려 주는 오라클이 된다.
     */
    public Optional<AuthCode> consume(String code) {
        if (code == null || code.isBlank()) {
            return Optional.empty();
        }

        // ① 1회성 — 꺼내는 즉시 없앤다. 이 한 줄이 "한 번 쓰면 죽는다" 의 전부다.
        AuthCode found = codes.remove(code);
        if (found == null) {
            return Optional.empty();
        }

        // ② 만료 — 발급 시각 + TTL 을 지났으면 없는 것과 같다.
        if (!clock.instant().isBefore(found.expiresAt())) {
            log.debug("만료된 1회용 코드가 제시되었다.");
            return Optional.empty();
        }

        return Optional.of(found);
    }

    /**
     * 만료된 코드를 치운다. 발급 때마다 부른다 — 별도 스케줄러를 두지 않는 이유는 이 맵이
     * 로그인 빈도만큼만 자라고, 자라는 순간이 곧 청소할 기회이기 때문이다.
     *
     * <p>아무도 로그인하지 않으면 청소도 멈추지만, 그때는 남아 있는 항목 수도 늘지 않는다.
     */
    private void purgeExpired() {
        Instant now = clock.instant();
        codes.entrySet().removeIf(entry -> !now.isBefore(entry.getValue().expiresAt()));
    }

    /** 설정된 수명. 0 이하면 코드가 발급 즉시 죽어 로그인이 성립하지 않으므로 막는다. */
    private long ttlSeconds() {
        long ttl = properties.getCodeTtlSeconds();
        if (ttl <= 0) {
            throw new IllegalStateException(
                    "app.security.oauth.code-ttl-seconds 는 0보다 커야 합니다. 현재: " + ttl);
        }
        return ttl;
    }

    /** 테스트·운영 점검용. 살아 있는 코드 수만 알려 준다 — 내용은 알려 주지 않는다. */
    public int size() {
        return codes.size();
    }
}
