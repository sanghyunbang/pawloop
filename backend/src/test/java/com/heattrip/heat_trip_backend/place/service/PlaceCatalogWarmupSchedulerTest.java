package com.heattrip.heat_trip_backend.place.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;

import java.lang.reflect.Method;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

/**
 * 예열 잡이 실제로 등록될 모양인지 본다 — 이슈 #279.
 *
 * <p>{@code RefreshTokenPurgeSchedulerTest} 와 같은 이유로 같은 것을 잰다. 잡 자체는 위임
 * 한 줄이라 {@code verify} 로 충분하고, cron 문자열을 그대로 견주는 이유는 하드코딩으로
 * 돌아가면 운영에서 시각을 못 옮기기 때문이며, {@code zone} 이 빠지면 서버 타임존에 따라
 * 실행 시각이 조용히 달라진다.
 *
 * <p>컨텍스트를 안 띄운다(#21). 빈이 실제로 뜨는지 안 뜨는지는
 * {@code PlaceCatalogWarmupWiringTest} 가 잰다.
 */
class PlaceCatalogWarmupSchedulerTest {

    @Test
    @DisplayName("스케줄 잡은 예열을 서비스에 그대로 위임한다")
    void scheduledJob_delegatesToTheService() {
        PlaceCatalogService catalog = mock(PlaceCatalogService.class);

        new PlaceCatalogWarmupScheduler(catalog).warmUpCatalog();

        verify(catalog).warmUp();
    }

    @Test
    @DisplayName("실행 주기는 설정으로 뺀 cron 이고 타임존이 Asia/Seoul 로 고정돼 있다")
    void scheduledJob_readsCronFromConfiguration() throws Exception {
        Method job = PlaceCatalogWarmupScheduler.class.getMethod("warmUpCatalog");
        Scheduled scheduled = job.getAnnotation(Scheduled.class);

        assertThat(scheduled)
                .as("애너테이션이 사라지면 첫 사용자가 매일 16초를 기다린다 — 그래도 앱은 멀쩡히 뜬다")
                .isNotNull();
        assertThat(scheduled.cron())
                .as("운영에서 시각을 옮길 수 있어야 한다. 04:40 은 리프레시 토큰 정리(04:30) 뒤다")
                .isEqualTo("${app.kto.catalog-warmup-cron:0 40 4 * * *}");
        assertThat(scheduled.zone()).isEqualTo("Asia/Seoul");
    }

    @Test
    @DisplayName("프로퍼티로 빈 자체를 끈다 — 테스트·CI 가 KTO 예산을 태우지 않게")
    void theBeanIsGatedByProperty() {
        ConditionalOnProperty gate =
                PlaceCatalogWarmupScheduler.class.getAnnotation(ConditionalOnProperty.class);

        assertThat(gate)
                .as("이게 없으면 테스트 컨텍스트가 뜰 때마다 잡이 등록되고, 시각이 맞으면 진짜 KTO 를 부른다")
                .isNotNull();
        assertThat(gate.prefix()).isEqualTo("app.kto");
        assertThat(gate.name()).containsExactly("catalog-warmup-enabled");
        assertThat(gate.havingValue()).isEqualTo("true");
        assertThat(gate.matchIfMissing())
                .as("프로퍼티가 빠졌을 때 켜지면 안 된다 — 빠진 것은 '끔' 이어야 한다")
                .isFalse();
    }
}
