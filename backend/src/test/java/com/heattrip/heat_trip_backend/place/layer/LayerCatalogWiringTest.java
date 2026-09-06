package com.heattrip.heat_trip_backend.place.layer;

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
 * 레이어 적재 잡의 배선 — 이슈 #291. {@code PlaceCatalogWarmupWiringTest} 와 같은 모양이다.
 */
class LayerCatalogWiringTest {

    @Nested
    @SpringBootTest
    @DisplayName("테스트 프로파일")
    class InTests extends AbstractMySqlIntegrationTest {

        @Autowired
        private ApplicationContext context;

        @Test
        @DisplayName("적재 잡 빈이 없다 — CI 가 공공데이터를 부르면 안 된다")
        void theSchedulerBeanIsAbsent() {
            assertThat(context.getBeanNamesForType(LayerCatalogScheduler.class))
                    .as("""
                            application-test.properties 의 app.place.layer.refresh-enabled=false 가 \
                            지워졌거나, 스케줄러의 @ConditionalOnProperty 가 그 이름을 안 본다""")
                    .isEmpty();
        }
    }

    @Nested
    @SpringBootTest(properties = {
            "app.place.layer.refresh-enabled=true",
            "app.place.layer.warm-up-on-start=false",
            "app.place.layer.refresh-cron=" + WhenEnabled.NEVER_DURING_CI })
    @DisplayName("프로퍼티를 켰을 때")
    class WhenEnabled extends AbstractMySqlIntegrationTest {

        static final String NEVER_DURING_CI = "0 0 0 29 2 *";

        @Autowired
        private ApplicationContext context;

        @Test
        @DisplayName("월 1회 잡이 등록되고 시각은 프로퍼티에서 읽는다")
        void theMonthlyJobIsRegisteredWithTheConfiguredCron() {
            Map<String, ScheduledTaskHolder> holders = context.getBeansOfType(ScheduledTaskHolder.class);
            String job = LayerCatalogScheduler.class.getName() + ".refreshMonthly";
            List<CronTask> jobs = holders.values().stream()
                    .flatMap(holder -> holder.getScheduledTasks().stream())
                    .map(ScheduledTask::getTask)
                    .filter(CronTask.class::isInstance)
                    .map(CronTask.class::cast)
                    .filter(task -> job.equals(String.valueOf(task)))
                    .toList();

            assertThat(jobs).as("빈은 떴는데 잡이 등록 목록에 없으면 @Scheduled 가 해석되지 않은 것이다").hasSize(1);
            assertThat(jobs.get(0).getExpression()).isEqualTo(NEVER_DURING_CI);
        }
    }
}
