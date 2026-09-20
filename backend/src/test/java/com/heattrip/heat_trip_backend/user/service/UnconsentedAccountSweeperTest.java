package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.user.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.UnconsentedAccounts;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 동의 없는 계정을 거두는 규칙 — 이슈 #660 완료 조건 4. 고정 시계로 경계를 재고, 삭제는 목으로 센다.
 *
 * <p>진짜 DB 에서 "누가 지워지고 누가 남는가" 는 {@code UnconsentedAccountSweepIntegrationTest} 가
 * 잰다. 여기는 그 사이의 규칙만 본다 — 경계 계산, 탈퇴 경로로의 위임, 멱등성, 실패 격리, 개수.
 */
class UnconsentedAccountSweeperTest {

    private static final Instant NOW = Instant.parse("2026-09-20T03:00:00Z");

    /**
     * 서비스 존(Asia/Seoul)으로 둔다. 경계는 존과 무관하게 <b>UTC</b> 여야 한다 —
     * {@code LocalDateTime.now(clock)} 으로 계산하면 KST 라 9시간이 밀리고, 이 시계가 그것을 잡는다.
     */
    private static final Clock CLOCK = Clock.fixed(NOW, ZoneId.of("Asia/Seoul"));

    private static final LocalDateTime A_DAY_BEFORE_NOW_UTC = LocalDateTime.of(2026, 9, 19, 3, 0);

    private final UnconsentedAccounts unconsented = mock(UnconsentedAccounts.class);
    private final UserService users = mock(UserService.class);
    private final SimpleMeterRegistry registry = new SimpleMeterRegistry();

    private UnconsentedAccountSweeper sweeper(long graceHours) {
        return new UnconsentedAccountSweeper(unconsented, users, CLOCK, registry, graceHours);
    }

    // ─────────────────────────── 경계 ───────────────────────────

    @Test
    @DisplayName("경계는 지금에서 유예를 뺀 UTC 시각이다 — 시계의 존이 KST 여도")
    void cutoff_isNowMinusGraceInUtc() {
        assertThat(sweeper(24).cutoff()).isEqualTo(A_DAY_BEFORE_NOW_UTC);
    }

    @Test
    @DisplayName("유예를 바꾸면 경계가 그만큼 움직인다 — 설정값이 실제로 쓰인다")
    void cutoff_movesWithTheConfiguredGrace() {
        assertThat(sweeper(1).cutoff()).isEqualTo(LocalDateTime.of(2026, 9, 20, 2, 0));
    }

    // ─────────────────────────── 거둔다 ───────────────────────────

    @Test
    @DisplayName("경계를 넘긴 동의 없는 계정을 탈퇴 경로로 하나씩 지우고 그 수를 돌려준다")
    void sweep_deletesEachAccountThroughWithdrawalAndCountsThem() {
        when(unconsented.idsCreatedBefore(A_DAY_BEFORE_NOW_UTC)).thenReturn(List.of(7L, 8L, 9L));

        int removed = sweeper(24).sweep();

        assertThat(removed).isEqualTo(3);
        verify(users).deleteMe(7L);
        verify(users).deleteMe(8L);
        verify(users).deleteMe(9L);
        assertThat(sweptCounter()).isEqualTo(3.0);
    }

    @Test
    @DisplayName("거둘 것이 없으면 0 이고 탈퇴를 한 번도 부르지 않는다")
    void sweep_withNothingPastTheGrace_deletesNobody() {
        when(unconsented.idsCreatedBefore(any())).thenReturn(List.of());

        int removed = sweeper(24).sweep();

        assertThat(removed).isZero();
        verify(unconsented).idsCreatedBefore(A_DAY_BEFORE_NOW_UTC);
        verify(users, never()).deleteMe(any());
        assertThat(sweptCounter()).isZero();
    }

    // ─────────────────────────── 멱등 · 격리 ───────────────────────────

    /**
     * 두 인스턴스가 같은 새벽에 함께 돌면 뒤에 온 쪽은 "그 주체가 더는 없다" 를 만난다. 그건 실패가
     * 아니라 결과가 같다는 뜻이다(#86 원칙 2) — 건너뛰고 나머지를 마저 지운다.
     */
    @Test
    @DisplayName("다른 인스턴스가 먼저 지운 계정은 건너뛰고 나머지는 지운다 — 세지도 않는다")
    void sweep_skipsAccountsAnotherInstanceAlreadyRemoved() {
        when(unconsented.idsCreatedBefore(any())).thenReturn(List.of(7L, 8L, 9L));
        doThrow(new UnauthenticatedException()).when(users).deleteMe(8L);

        int removed = sweeper(24).sweep();

        assertThat(removed).isEqualTo(2);
        verify(users).deleteMe(9L);
        assertThat(sweptCounter()).isEqualTo(2.0);
    }

    @Test
    @DisplayName("한 계정에서 예외가 나도 나머지는 지운다 — 계정마다 따로다")
    void sweep_keepsGoingWhenOneAccountFails() {
        when(unconsented.idsCreatedBefore(any())).thenReturn(List.of(7L, 8L, 9L));
        doThrow(new IllegalStateException("row count 0")).when(users).deleteMe(8L);

        int removed = sweeper(24).sweep();

        assertThat(removed).isEqualTo(2);
        verify(users).deleteMe(7L);
        verify(users).deleteMe(9L);
    }

    private double sweptCounter() {
        return registry.get("user.account.swept").tag("reason", "consent_missing").counter().count();
    }
}
