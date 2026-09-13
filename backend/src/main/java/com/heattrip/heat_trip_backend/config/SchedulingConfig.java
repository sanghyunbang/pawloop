package com.heattrip.heat_trip_backend.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * {@code @Scheduled} 를 켠다. (이슈 #9)
 *
 * <p>지금까지 이 저장소에는 {@code @EnableScheduling} 이 없었다. 켜면서 다른 잡이 함께
 * 깨어나지 않는지 확인했다 — 저장소의 유일한 다른 {@code @Scheduled}
 * ({@code tour.schedules.TourFetchScheduler})는 애너테이션이 <b>주석 처리</b>돼 있어
 * 스케줄 등록 대상이 아니다. 즉 이 설정이 실제로 켜는 잡은 처음엔
 * {@code RefreshTokenPurgeScheduler} 하나뿐이었다.
 *
 * <p>2026-09-05 에 {@code PlaceCatalogWarmupScheduler}(#279) 가 더해졌다 — 프로퍼티
 * {@code app.kto.catalog-warmup-enabled} 로 켜고 끄며, 테스트 프로파일에서는 빈 자체가
 * 안 뜬다. 2026-09-13 에 {@code S3.media.MediaOrphanSweeper}(#429) 가 더해졌다 — 새벽 4:10,
 * 붙지 않은 글 미디어를 거둔다. 다른 {@code @Scheduled} 를 되살릴 때는 이 목록이 바뀐다는
 * 것을 알고 되살릴 것.
 */
@Configuration
@EnableScheduling
public class SchedulingConfig {
}
