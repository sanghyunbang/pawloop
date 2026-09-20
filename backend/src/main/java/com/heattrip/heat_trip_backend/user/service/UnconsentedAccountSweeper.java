package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.user.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.UnconsentedAccounts;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;

import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.List;

/**
 * 동의 없이 하루가 지난 계정을 거둔다 — 이슈 #660 완료 조건 4.
 *
 * <h2>왜 있나</h2>
 *
 * <p>토큰이 동의보다 먼저 발급된다 — 소셜 로그인이 끝나는 순간 계정이 생긴다. 그 뒤 동의 화면에서
 * 앱을 지우면 <b>아무 동의도 받지 않은 개인정보</b>(닉네임·이메일)가 서버에 남는다.
 * {@code security.ConsentRequiredFilter} 가 그 계정의 요청은 막지만, 남아 있는 것 자체가 문제다
 * (개인정보보호법 제15조 — 수집 전 동의). 이 클래스가 그것을 거둔다.
 *
 * <h2>지우는 길은 탈퇴 그대로다</h2>
 *
 * <p>새 삭제 로직을 두지 않는다. {@link UserService#deleteMe} — refresh 토큰을 먼저 지우고,
 * {@code users} 행을 지우고, {@code UserSessionsRevoked(accountDeleted = true)} 를 내보내 기기
 * 토큰까지 정리되는 그 길 — 을 계정마다 부른다. 지우는 길이 둘이면 한쪽만 고쳐지는 날이 온다.
 *
 * <h2>이 코드가 같은 DB 를 향해 동시에 두 번 실행돼도 결과가 같다 (#86 원칙 2)</h2>
 *
 * <p>계정마다 {@code deleteMe} 의 트랜잭션 하나다 — 이 메서드에는 일부러 {@code @Transactional} 을
 * 안 붙였다. 붙이면 한 계정의 실패가 그날 밤 전부를 되돌리고, 커밋 뒤에 도는 기기 토큰 정리도
 * 마지막에 몰린다. 다른 인스턴스가 먼저 지운 계정은 {@link UnauthenticatedException}("그 주체가
 * 더는 없다")으로 돌아오므로 건너뛴다. 그 사이에 지워져 {@code delete} 가 다른 예외로 실패해도
 * 다음 계정으로 간다 — 어느 쪽이든 그 계정은 이미 없다.
 *
 * <h2>한 장씩 읽는다 — 자기 표에서</h2>
 *
 * <p>유예가 지난 계정은 곧 <b>가입자 거의 전부</b>다. 그 id 를 통째로 들지 않고 {@value #PAGE_SIZE}
 * 개씩 id 순으로 읽어(키셋 — 앞 장의 계정을 지워도 다음 장이 밀리지 않는다) 그 장에 대해서만
 * {@link UnconsentedAccounts} 에 묻는다. 시각으로 거르는 것은 {@code users.created_at} 이라 이
 * 모듈의 일이고, 동의 여부는 {@code user_consent} 라 저쪽의 일이다 — 어느 쪽 쿼리도 남의 표를
 * 안 부른다({@code CrossModuleQueryJoinsTest}). 밤에 가벼운 쿼리가 장 수의 두 배만큼 나가는 것이
 * 남의 스키마에 묶이는 것보다 싸다.
 *
 * <h2>무엇을 "동의 없음" 으로 보나</h2>
 *
 * <p>여기서는 정하지 않는다. {@link UnconsentedAccounts} 가 정하고 {@code consent} 가 답한다 —
 * "필수 셋 중 하나라도 <b>한 번도</b> 동의한 행이 없다". 철회는 세지 않는다. 그 이유는 그
 * 인터페이스의 javadoc 에 있다.
 *
 * <h2>0건도 적는다</h2>
 *
 * <p>다른 정리 잡은 지운 것이 있을 때만 로그를 남기는데, 계정을 지우는 잡은 <b>돌았다는 사실
 * 자체가 근거</b>라 매번 개수를 적는다. 하루 한 줄이다. 개수만 적고 id 는 안 적는다 — 지워진
 * 사람의 흔적을 로그에 남길 이유가 없다. {@code user.account.swept} 카운터가 같은 수를 센다.
 *
 * <p>여기는 정리만 하고 시각은 {@link UnconsentedAccountSweepScheduler} 가 정한다 —
 * {@code RefreshTokenPurgeScheduler} → {@code RefreshTokenService} 와 같은 나눔이다. 그래야
 * 고정 {@link Clock} 으로 경계를 벽시계 없이 잰다.
 */
@Service
public class UnconsentedAccountSweeper {

    private static final Logger log = LoggerFactory.getLogger(UnconsentedAccountSweeper.class);

    /** 한 장에 읽는 id 수. 500 이면 IN 절 하나로 묻기에 넉넉하고 한 장이 커넥션을 오래 잡지 않는다. */
    static final int PAGE_SIZE = 500;

    private final UserRepository userRepository;
    private final UnconsentedAccounts unconsented;
    private final UserService users;
    private final Clock clock;
    private final Duration grace;
    private final Counter swept;

    public UnconsentedAccountSweeper(UserRepository userRepository,
                                     UnconsentedAccounts unconsented,
                                     UserService users,
                                     Clock clock,
                                     MeterRegistry registry,
                                     @Value("${app.consent.cleanup.grace-hours:24}") long graceHours) {
        this.userRepository = userRepository;
        this.unconsented = unconsented;
        this.users = users;
        this.clock = clock;
        this.grace = Duration.ofHours(graceHours);
        // 첫 실행 전에도 0 으로 노출되어야 "지표가 없는 것" 과 "0인 것" 이 구분된다 (ChatMetrics 와 같다).
        this.swept = Counter.builder("user.account.swept")
                .description("동의 없이 유예 시간이 지나 거둔 계정 수")
                .tag("reason", "consent_missing")
                .register(registry);
    }

    /**
     * 유예가 지난 동의 없는 계정을 전부 거둔다.
     *
     * @return 이번 실행에서 실제로 지운 수. 다른 인스턴스가 먼저 지운 것은 세지 않는다
     */
    public int sweep() {
        LocalDateTime cutoff = cutoff();
        int removed = 0;
        long afterId = 0;
        while (true) {
            List<Long> page = userRepository.findIdsCreatedBefore(cutoff, afterId, PageRequest.of(0, PAGE_SIZE));
            if (page.isEmpty()) {
                break;
            }
            for (Long id : unconsented.among(page)) {
                if (remove(id)) {
                    removed++;
                }
            }
            afterId = page.get(page.size() - 1); // id 순이라 마지막이 가장 크다 — 다음 장은 그 뒤부터
        }
        swept.increment(removed);
        log.info("[consent] 필수 약관에 동의하지 않은 채 {}시간 지난 계정 {}건을 거뒀다", grace.toHours(), removed);
        return removed;
    }

    /** 탈퇴 경로로 하나를 지운다. 이미 없거나 실패하면 {@code false} — 어느 쪽이든 다음 계정으로 간다. */
    private boolean remove(long userId) {
        try {
            users.deleteMe(userId);
            return true;
        } catch (UnauthenticatedException alreadyGone) {
            // 다른 인스턴스가 먼저 지웠거나 그 사이에 스스로 탈퇴했다. 결과는 같다.
            return false;
        } catch (RuntimeException e) {
            log.warn("[consent] 동의 없는 계정 하나를 거두지 못했다 — 다음 실행에 다시 본다: {}", e.toString());
            return false;
        }
    }

    /**
     * 이 시각보다 먼저 만들어진 계정이 대상이다 — UTC 를 담은 {@code LocalDateTime}
     * ({@code users.created_at} 의 규약, {@code UserTime}). 테스트가 같은 계산을 쓰게 밖에 둔다.
     */
    public LocalDateTime cutoff() {
        return LocalDateTime.ofInstant(clock.instant().minus(grace), ZoneOffset.UTC);
    }
}
