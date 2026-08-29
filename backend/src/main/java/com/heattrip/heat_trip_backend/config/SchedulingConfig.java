package com.heattrip.heat_trip_backend.config;

import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * {@code @Scheduled} 를 켠다. (이슈 #9)
 *
 * <p>지금까지 이 저장소에는 {@code @EnableScheduling} 이 없었다. 켜면서 다른 잡이 함께
 * 깨어나지 않는지 확인했다 — 저장소의 유일한 다른 {@code @Scheduled}
 * ({@code tour.schedules.TourFetchScheduler})는 애너테이션이 <b>주석 처리</b>돼 있어
 * 스케줄 등록 대상이 아니다. 즉 이 설정이 실제로 켜는 잡은
 * {@code RefreshTokenPurgeScheduler} 하나뿐이다.
 *
 * <p>다른 {@code @Scheduled} 를 되살릴 때는 이 사실이 바뀐다는 것을 알고 되살릴 것.
 */
@Configuration
@EnableScheduling
public class SchedulingConfig {
}
