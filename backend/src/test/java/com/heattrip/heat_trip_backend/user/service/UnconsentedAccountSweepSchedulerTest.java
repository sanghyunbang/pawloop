package com.heattrip.heat_trip_backend.user.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;

import java.lang.reflect.Method;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

/**
 * 동의 없는 계정 청소 잡이 실제로 등록될 모양인지 본다 — 이슈 #660.
 *
 * <p>{@code RefreshTokenPurgeSchedulerTest}·{@code PlaceCatalogWarmupSchedulerTest} 와 같은 이유로
 * 같은 것을 잰다. 잡 자체는 위임 한 줄이라 {@code verify} 로 충분하고, cron 문자열을 그대로 견주는
 * 이유는 하드코딩으로 돌아가면 운영에서 시각을 못 옮기기 때문이며, {@code zone} 이 빠지면 서버
 * 타임존에 따라 실행 시각이 조용히 달라진다.
 *
 * <p>컨텍스트를 안 띄운다(#21). 빈이 실제로 뜨는지 안 뜨는지는
 * {@code UnconsentedAccountSweepWiringTest} 가 잰다.
 */
class UnconsentedAccountSweepSchedulerTest {

    @Test
    @DisplayName("스케줄 잡은 청소를 서비스에 그대로 위임한다")
    void scheduledJob_delegatesToTheSweeper() {
        UnconsentedAccountSweeper sweeper = mock(UnconsentedAccountSweeper.class);

        new UnconsentedAccountSweepScheduler(sweeper).sweepUnconsentedAccounts();

        verify(sweeper).sweep();
    }

    @Test
    @DisplayName("실행 주기는 설정으로 뺀 cron 이고 타임존이 Asia/Seoul 로 고정돼 있다")
    void scheduledJob_readsCronFromConfiguration() throws Exception {
        Method job = UnconsentedAccountSweepScheduler.class.getMethod("sweepUnconsentedAccounts");
        Scheduled scheduled = job.getAnnotation(Scheduled.class);

        assertThat(scheduled)
                .as("애너테이션이 사라지면 동의 없는 계정이 영원히 쌓인다 — 그래도 앱은 멀쩡히 뜬다")
                .isNotNull();
        assertThat(scheduled.cron())
                .as("운영에서 시각을 옮길 수 있어야 한다. 04:50 은 가입 대기 정리(04:40) 뒤다")
                .isEqualTo("${app.consent.cleanup.cron:0 50 4 * * *}");
        assertThat(scheduled.zone())
                .as("zone 이 없으면 서버 타임존에 따라 실행 시각이 조용히 달라진다")
                .isEqualTo("Asia/Seoul");
    }

    @Test
    @DisplayName("프로퍼티로 빈 자체를 끈다 — 기본은 켬이고, 테스트 프로파일이 명시적으로 끈다")
    void theBeanIsGatedByProperty_defaultOn() {
        ConditionalOnProperty gate =
                UnconsentedAccountSweepScheduler.class.getAnnotation(ConditionalOnProperty.class);

        assertThat(gate)
                .as("이게 없으면 테스트 컨텍스트가 뜰 때마다 계정을 지우는 잡이 등록된다")
                .isNotNull();
        assertThat(gate.prefix()).isEqualTo("app.consent.cleanup");
        assertThat(gate.name()).containsExactly("enabled");
        assertThat(gate.havingValue()).isEqualTo("true");
        assertThat(gate.matchIfMissing())
                .as("""
                        개인정보를 거두는 잡은 프로퍼티를 빠뜨렸다고 조용히 안 도는 쪽이 더 나쁘다 — \
                        외부 예산을 태우는 예열 잡(빠지면 끔)과 반대다. 끄는 것은 명시적으로 한다""")
                .isTrue();
    }
}
