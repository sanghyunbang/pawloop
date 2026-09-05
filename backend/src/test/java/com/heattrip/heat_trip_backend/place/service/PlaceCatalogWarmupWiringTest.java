package com.heattrip.heat_trip_backend.place.service;

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
 * 예열 잡의 배선 — 이슈 #279.
 *
 * <h2>두 가지를 잰다</h2>
 * <ol>
 *   <li><b>테스트 프로파일에서는 빈이 없다.</b> 있으면 CI 가 뜰 때마다 잡이 등록되고, 시각이
 *       맞으면 진짜 KTO 를 부른다. {@code application-test.properties} 의 한 줄이 그것을
 *       막는데, 그 줄이 사라져도 아무도 모른다 — 여기서 잠근다.</li>
 *   <li><b>프로퍼티를 켜면 실제로 등록된다.</b> {@code @Scheduled} 는 {@code @EnableScheduling}
 *       없이는 무력하고, 조건부 빈은 프로퍼티 이름이 한 글자만 틀려도 조용히 안 뜬다. 등록된
 *       잡 목록에서 이 메서드를 찾는다({@code RefreshTokenOperationalWiringIntegrationTest} 와
 *       같은 방법).</li>
 * </ol>
 *
 * <p>둘째 컨텍스트에서도 잡이 <b>실행되지는 않는다</b> — cron 이 04:40 이라 테스트가 도는
 * 동안 그 시각이 올 일이 없다. 그래도 KTO 를 부를 경로가 생기는 것은 맞으므로 켜는 것은
 * 이 클래스 안의 한 컨텍스트뿐이다.
 */
class PlaceCatalogWarmupWiringTest {

    @Nested
    @SpringBootTest
    @DisplayName("테스트 프로파일")
    class InTests extends AbstractMySqlIntegrationTest {

        @Autowired
        private ApplicationContext context;

        @Test
        @DisplayName("예열 잡 빈이 없다 — CI 가 KTO 예산을 태우면 안 된다")
        void theWarmupBeanIsAbsent() {
            assertThat(context.getBeanNamesForType(PlaceCatalogWarmupScheduler.class))
                    .as("""
                            application-test.properties 의 app.kto.catalog-warmup-enabled=false 가 \
                            지워졌거나, 스케줄러의 @ConditionalOnProperty 가 그 이름을 안 본다""")
                    .isEmpty();
        }
    }

    /**
     * 켜는 컨텍스트는 cron 을 <b>2월 29일 0시</b>로 준다. 잡이 등록되는 것과 프로퍼티가 실제로
     * 읽히는 것을 한 번에 재면서, CI 가 도는 동안 잡이 실제로 돌 일이 없게 한다 — 다음 2월
     * 29일은 2028년이다.
     */
    @Nested
    @SpringBootTest(properties = {
            "app.kto.catalog-warmup-enabled=true",
            "app.kto.catalog-warmup-cron=" + WhenEnabled.NEVER_DURING_CI })
    @DisplayName("프로퍼티를 켰을 때")
    class WhenEnabled extends AbstractMySqlIntegrationTest {

        static final String NEVER_DURING_CI = "0 0 0 29 2 *";

        @Autowired
        private ApplicationContext context;

        @Test
        @DisplayName("예열 잡이 살아 있는 컨텍스트에 등록되고, 시각은 프로퍼티에서 읽는다")
        void theWarmupJobIsRegisteredWithTheConfiguredCron() {
            Map<String, ScheduledTaskHolder> holders = context.getBeansOfType(ScheduledTaskHolder.class);
            assertThat(holders).as("@EnableScheduling 이 빠지면 여기가 비어 있다").isNotEmpty();

            // 등록된 잡의 표현은 Task#toString() 이고 그건 대상 메서드의 FQN 이다. 러너블 타입으로
            // 거르지 않는 이유: Spring 6.1+ 가 관측을 위해 ScheduledMethodRunnable 을
            // Task$OutcomeTrackingRunnable 로 감싸서, 타입 검사로 거르면 전부 빠져나간다(실측 —
            // 이 테스트의 첫 판이 그렇게 0건으로 빨갰다).
            String job = PlaceCatalogWarmupScheduler.class.getName() + ".warmUpCatalog";
            List<CronTask> warmups = holders.values().stream()
                    .flatMap(holder -> holder.getScheduledTasks().stream())
                    .map(ScheduledTask::getTask)
                    .filter(CronTask.class::isInstance)
                    .map(CronTask.class::cast)
                    .filter(task -> job.equals(String.valueOf(task)))
                    .toList();

            assertThat(warmups)
                    .as("빈은 떴는데 잡이 등록 목록에 없으면 @Scheduled 가 해석되지 않은 것이다")
                    .hasSize(1);
            assertThat(warmups.get(0).getExpression())
                    .as("운영에서 APP_KTO_CATALOG_WARMUP_CRON 으로 시각을 옮길 수 있어야 한다")
                    .isEqualTo(NEVER_DURING_CI);
        }
    }
}
