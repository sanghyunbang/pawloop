package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.consent.ConsentKind;
import com.heattrip.heat_trip_backend.consent.entity.UserConsent;
import com.heattrip.heat_trip_backend.consent.repository.UserConsentRepository;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import io.micrometer.core.instrument.MeterRegistry;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 동의 없이 하루 지난 계정을 거둔다 — 이슈 #660 완료 조건 4. 진짜 MySQL 위에서 누가 지워지고
 * 누가 남는지를 잰다.
 *
 * <h2>왜 트랜잭션 테스트가 아닌가</h2>
 *
 * <p>거두는 길은 <b>계정마다 트랜잭션 하나</b>다({@code UserService.deleteMe}). 테스트를
 * {@code @Transactional} 로 감싸면 그 경계가 테스트 트랜잭션에 묻혀 "한 계정의 실패가 나머지를
 * 되돌리지 않는다" 가 실제로는 잴 수 없게 된다. 대신 만든 행을 {@link #cleanUp} 이 직접 지운다 —
 * {@code RefreshTokenOperationalWiringIntegrationTest} 와 같은 방식이다.
 *
 * <h2>시각을 과거로 옮기는 법</h2>
 *
 * <p>{@code users.created_at} 은 {@code @PrePersist} 가 UTC 로 찍는다. 그 값을 SQL 로 뒤로 민다 —
 * {@code MediaAttachmentIntegrationTest} 가 미디어 행에 하는 것과 같다. 경계도 UTC 라
 * ({@code UnconsentedAccountSweeper.cutoff}) 두 값이 같은 눈금 위에 있다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄인 것은 의도다 —
 * 다른 통합 테스트와 글자 그대로 같아야 스프링 컨텍스트 캐시를 공유한다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
class UnconsentedAccountSweepIntegrationTest extends AbstractMySqlIntegrationTest {

    @Autowired private UnconsentedAccountSweeper sweeper;
    @Autowired private UserRepository userRepository;
    @Autowired private UserConsentRepository consentRepository;
    @Autowired private RefreshTokenService refreshTokenService;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private MeterRegistry registry;

    private final List<Long> createdUserIds = new ArrayList<>();

    @AfterEach
    void cleanUp() {
        for (Long id : createdUserIds) {
            jdbc.update("DELETE FROM refresh_token WHERE user_id = ?", id);
            jdbc.update("DELETE FROM user_consent WHERE user_id = ?", id);
            jdbc.update("DELETE FROM users WHERE id = ?", id);
        }
        createdUserIds.clear();
    }

    // ─────────────────────────── 거둔다 ───────────────────────────

    @Test
    @DisplayName("동의 없이 25시간 지난 계정은 사라지고, 그 사람의 refresh 토큰 행도 없다 — 거둔 수가 셈에 오른다")
    void neverConsented_pastGrace_isRemovedWithItsTokens() {
        long id = seed("never").getId();
        refreshTokenService.issueFor(id);
        madeHoursAgo(id, 25);
        double sweptBefore = sweptCounter();

        int removed = sweeper.sweep();

        assertThat(removed).isEqualTo(1);
        assertThat(userRepository.findById(id)).as("동의 없는 계정이 남았다").isEmpty();
        assertThat(refreshTokenRows(id)).as("탈퇴 경로가 아니면 RT 행이 남는다").isZero();
        assertThat(sweptCounter() - sweptBefore).isEqualTo(1.0);
    }

    /**
     * 앱은 필수 셋을 한 번에 보내므로 이 상태는 앱을 거치지 않고 일부만 적은 경우다. 그 계정도
     * {@code ConsentRequiredFilter} 에 막혀 아무것도 못 하는 계정이라 같이 거둔다(ㄴ).
     */
    @Test
    @DisplayName("필수 중 둘만 적은 25시간 전 계정은 거둔다 — 동의 행은 증빙으로 남는다")
    void partiallyConsented_pastGrace_isRemovedButItsConsentRowsStay() {
        long id = seed("partial").getId();
        consentRow(id, ConsentKind.TERMS, true);
        consentRow(id, ConsentKind.PRIVACY, true);
        madeHoursAgo(id, 25);

        sweeper.sweep();

        assertThat(userRepository.findById(id)).isEmpty();
        assertThat(consentRepository.findByUserIdOrderByIdDesc(id))
                .as("user_consent 는 users 로 FK 가 없다 — 지워진 계정의 동의 증빙은 남아야 한다")
                .hasSize(2);
    }

    @Test
    @DisplayName("위치를 거절(agreed=false)로 적은 채 25시간 지난 계정은 거둔다 — 거절은 동의가 아니다")
    void declinedARequiredKind_pastGrace_isRemoved() {
        long id = seed("declined").getId();
        consentRow(id, ConsentKind.TERMS, true);
        consentRow(id, ConsentKind.PRIVACY, true);
        consentRow(id, ConsentKind.LOCATION, false);
        madeHoursAgo(id, 25);

        sweeper.sweep();

        assertThat(userRepository.findById(id)).isEmpty();
    }

    // ─────────────────────────── 남긴다 ───────────────────────────

    @Test
    @DisplayName("동의 안 했지만 1시간 전에 만든 계정은 남는다 — 동의 화면을 보고 있는 사람이다")
    void neverConsented_withinGrace_stays() {
        long id = seed("fresh").getId();
        madeHoursAgo(id, 1);

        sweeper.sweep();

        assertThat(userRepository.findById(id)).isPresent();
    }

    @Test
    @DisplayName("필수 셋에 다 동의한 25시간 전 계정은 남는다")
    void fullyConsented_pastGrace_stays() {
        long id = consented(seed("consented")).getId();
        madeHoursAgo(id, 25);

        sweeper.sweep();

        assertThat(userRepository.findById(id)).isPresent();
    }

    @Test
    @DisplayName("마케팅(선택)만 빠진 25시간 전 계정은 남는다 — 필수만 본다")
    void onlyMarketingMissing_pastGrace_stays() {
        long id = consented(seed("no-marketing")).getId();
        consentRow(id, ConsentKind.MARKETING, false);
        madeHoursAgo(id, 25);

        sweeper.sweep();

        assertThat(userRepository.findById(id)).isPresent();
    }

    /**
     * 철회는 기록이지 이탈이 아니다(ADR-0020). 철회한 사람의 처지는 필터(403)가 정하고, 계정은 남는다 —
     * "지금 동의 상태" 로 거두면 1년 된 계정이 철회한 다음 날 새벽에 사라진다.
     */
    @Test
    @DisplayName("동의했다가 철회한 25시간 전 계정은 남는다 — 철회는 이탈이 아니다")
    void revokedAfterConsenting_pastGrace_stays() {
        long id = consented(seed("revoked")).getId();
        consentRow(id, ConsentKind.LOCATION, false); // 마지막 행이 철회 — "지금" 은 동의 상태가 아니다
        madeHoursAgo(id, 25);

        sweeper.sweep();

        assertThat(userRepository.findById(id)).isPresent();
    }

    @Test
    @DisplayName("언제 만들어졌는지 모르는(created_at 이 빈) 계정은 건드리지 않는다")
    void unknownCreationTime_stays() {
        long id = seed("no-date").getId();
        jdbc.update("UPDATE users SET created_at = NULL WHERE id = ?", id);

        sweeper.sweep();

        assertThat(userRepository.findById(id)).isPresent();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private User seed(String tag) {
        String unique = tag + "-" + System.nanoTime();
        User saved = userRepository.save(User.builder()
                .provider("kakao")
                .socialId(unique)
                .username("kakao_" + unique)
                .role(User.ROLE_USER)
                .email(unique + "@example.test")
                .name("보리")
                .nickname("보리")
                .build());
        createdUserIds.add(saved.getId());
        return saved;
    }

    /** {@code created_at} 을 뒤로 민다. 저장된 값이 UTC 라 경계({@code cutoff}, UTC)와 같은 눈금이다. */
    private void madeHoursAgo(long userId, int hours) {
        jdbc.update("UPDATE users SET created_at = created_at - INTERVAL " + hours + " HOUR WHERE id = ?", userId);
    }

    private void consentRow(long userId, ConsentKind kind, boolean agreed) {
        consentRepository.save(UserConsent.builder()
                .userId(userId)
                .kind(kind.name())
                .version("v1.0")
                .agreed(agreed)
                .createdAt(LocalDateTime.now(ZoneOffset.UTC))
                .build());
    }

    private long refreshTokenRows(long userId) {
        Long rows = jdbc.queryForObject("SELECT COUNT(*) FROM refresh_token WHERE user_id = ?", Long.class, userId);
        return rows == null ? 0 : rows;
    }

    private double sweptCounter() {
        return registry.get("user.account.swept").tag("reason", "consent_missing").counter().count();
    }
}
