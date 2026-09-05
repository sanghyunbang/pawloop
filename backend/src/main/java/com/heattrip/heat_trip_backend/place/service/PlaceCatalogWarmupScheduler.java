package com.heattrip.heat_trip_backend.place.service;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 전국 카탈로그를 매일 새벽에 미리 받아 둔다 — 이슈 #279.
 *
 * <h2>왜 새벽 cron 인가 — 부팅 예열이 아니라</h2>
 * <p>한 벌은 24시간이 지나면 낡은 것으로 보고, 낡은 뒤 <b>처음 지도를 여는 사람</b>이
 * 관광공사 10콜(실측 16초)을 기다린다. 서버가 켜질 때 받는 것은 배포한 날만 해결한다 —
 * 서버가 며칠 안 꺼지면 다음 날부터 또 첫 사람이 기다린다. 매일 정해진 시각에 받아야
 * 아무도 안 기다린다.
 *
 * <h2>서버가 여러 대여도 예산이 안 새는 이유</h2>
 * <p>같은 시각에 각자 돌지만 {@link PlaceCatalogService} 가 DB 의 {@code fetched_at} 을
 * 보고 낡지 않았으면 안 받는다. 정확히 같은 초에 겹치면 둘 다 받을 수 있는데, 그래도 20콜이라
 * 하루 예산(50) 안이다. 사용자 요청과 같은 예산 풀·같은 백오프를 쓴다 — 예열이 특권을
 * 갖지 않는다.
 *
 * <h2>테스트·CI 에서는 빈 자체가 안 뜬다</h2>
 * <p>{@code app.kto.catalog-warmup-enabled=false} 면 이 클래스가 컨텍스트에 없다.
 * {@code @Scheduled} 만 조건부로 두면 빈은 뜨고 잡만 안 걸리는데, 그 상태를 테스트로 재기가
 * 어렵다 — 빈의 유무는 잴 수 있다. {@code backfill.kakao.enabled} 가 같은 모양이다.
 *
 * <p>여기는 시각만 정한다. 무엇을 하는지는 {@link PlaceCatalogService#warmUp()} 이 안다 —
 * {@code RefreshTokenPurgeScheduler} 와 같은 나눔이다.
 */
@Component
@ConditionalOnProperty(prefix = "app.kto", name = "catalog-warmup-enabled", havingValue = "true")
public class PlaceCatalogWarmupScheduler {

    private final PlaceCatalogService catalog;

    public PlaceCatalogWarmupScheduler(PlaceCatalogService catalog) {
        this.catalog = catalog;
    }

    @Scheduled(cron = "${app.kto.catalog-warmup-cron:0 40 4 * * *}", zone = "Asia/Seoul")
    public void warmUpCatalog() {
        catalog.warmUp();
    }
}
