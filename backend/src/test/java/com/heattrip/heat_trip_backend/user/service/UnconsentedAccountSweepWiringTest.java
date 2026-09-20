package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.scheduling.config.CronTask;
import org.springframework.scheduling.config.ScheduledTask;
import org.springframework.scheduling.config.ScheduledTaskHolder;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 동의 없는 계정 청소 잡의 배선 — 이슈 #660 완료 조건 4.
 *
 * <h2>두 가지를 잰다</h2>
 * <ol>
 *   <li><b>테스트 프로파일에서는 빈이 없다.</b> 있으면 CI 가 뜰 때마다 계정을 지우는 잡이 등록되고,
 *       새벽 시각에 CI 가 돌면 다른 테스트가 만든 사용자를 지운다. 운영 기본값이 켬
 *       ({@code matchIfMissing}) 이라 {@code application-test.properties} 의 한 줄이 그것을 끄는데,
 *       그 줄이 사라져도 아무도 모른다 — 여기서 잠근다.</li>
 *   <li><b>프로퍼티를 켜면 실제로 등록된다.</b> {@code @Scheduled} 는 {@code @EnableScheduling}
 *       없이는 무력하고, 조건부 빈은 프로퍼티 이름이 한 글자만 틀려도 조용히 안 뜬다. 등록된
 *       잡 목록에서 이 메서드를 찾는다({@code PlaceCatalogWarmupWiringTest} 와 같은 방법).</li>
 * </ol>
 *
 * <p>둘째 컨텍스트에서도 잡이 <b>실행되지는 않는다</b> — cron 을 2월 29일 0시로 준다.
 */
class UnconsentedAccountSweepWiringTest {

    @Nested
    @SpringBootTest
    @DisplayName("테스트 프로파일")
    class InTests extends AbstractMySqlIntegrationTest {

        @Autowired
        private ApplicationContext context;

        @Test
        @DisplayName("청소 잡 빈이 없다 — CI 가 시드 사용자를 지우면 안 된다")
        void theSweepSchedulerBeanIsAbsent() {
            assertThat(context.getBeanNamesForType(UnconsentedAccountSweepScheduler.class))
                    .as("""
                            application-test.properties 의 app.consent.cleanup.enabled=false 가 \
                            지워졌거나, 스케줄러의 @ConditionalOnProperty 가 그 이름을 안 본다""")
                    .isEmpty();
        }

        @Test
        @DisplayName("정리 자체(서비스)는 그대로 있다 — 잡만 없는 것이다")
        void theSweeperItselfIsStillThere() {
            assertThat(context.getBeanNamesForType(UnconsentedAccountSweeper.class))
                    .as("서비스까지 조건부로 두면 통합 테스트가 규칙을 잴 수 없다")
                    .hasSize(1);
        }
    }

    /**
     * 켜는 컨텍스트는 cron 을 <b>2월 29일 0시</b>로 준다. 잡이 등록되는 것과 프로퍼티가 실제로
     * 읽히는 것을 한 번에 재면서, CI 가 도는 동안 잡이 실제로 돌 일이 없게 한다.
     */
    @Nested
    @SpringBootTest(properties = {
            "app.consent.cleanup.enabled=true",
            "app.consent.cleanup.cron=" + WhenEnabled.NEVER_DURING_CI })
    @DisplayName("프로퍼티를 켰을 때")
    class WhenEnabled extends AbstractMySqlIntegrationTest {

        static final String NEVER_DURING_CI = "0 0 0 29 2 *";

        @Autowired
        private ApplicationContext context;

        @Test
        @DisplayName("청소 잡이 살아 있는 컨텍스트에 등록되고, 시각은 프로퍼티에서 읽는다")
        void theSweepJobIsRegisteredWithTheConfiguredCron() {
            Map<String, ScheduledTaskHolder> holders = context.getBeansOfType(ScheduledTaskHolder.class);
            assertThat(holders).as("@EnableScheduling 이 빠지면 여기가 비어 있다").isNotEmpty();

            // 등록된 잡의 표현은 Task#toString() 이고 그건 대상 메서드의 FQN 이다. 러너블 타입으로
            // 거르지 않는 이유는 PlaceCatalogWarmupWiringTest 에 있다 — Spring 6.1+ 가 감싼다.
            String job = UnconsentedAccountSweepScheduler.class.getName() + ".sweepUnconsentedAccounts";
            List<CronTask> sweeps = holders.values().stream()
                    .flatMap(holder -> holder.getScheduledTasks().stream())
                    .map(ScheduledTask::getTask)
                    .filter(CronTask.class::isInstance)
                    .map(CronTask.class::cast)
                    .filter(task -> job.equals(String.valueOf(task)))
                    .toList();

            assertThat(sweeps)
                    .as("빈은 떴는데 잡이 등록 목록에 없으면 @Scheduled 가 해석되지 않은 것이다")
                    .hasSize(1);
            assertThat(sweeps.get(0).getExpression())
                    .as("운영에서 APP_CONSENT_CLEANUP_CRON 으로 시각을 옮길 수 있어야 한다")
                    .isEqualTo(NEVER_DURING_CI);
        }
    }
}
