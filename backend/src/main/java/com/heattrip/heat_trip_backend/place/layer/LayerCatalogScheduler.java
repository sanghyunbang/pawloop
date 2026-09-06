package com.heattrip.heat_trip_backend.place.layer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * 공공데이터 레이어를 <b>월 1회</b> 다시 받고, 기동 직후 없으면 뒤에서 채운다 — 이슈 #291.
 *
 * <p>KTO 예열({@code PlaceCatalogWarmupScheduler})과 따로인 이유: 주기가 다르다. 인허가는
 * 느리게 바뀌고 두루누비는 거의 정적이라 매일 받으면 예산만 태운다. 기본 시각은 매월 1일
 * 05:20(KST) — KTO 예열(04:40) 뒤다.
 *
 * <h2>기동 예열</h2>
 * <p>배포한 날 다음 달 1일까지 병원·펫샵·산책로 칩이 비면 안 된다. 그래서 컨텍스트가 뜬 뒤
 * 한 벌이 없거나 낡았으면 <b>별도 스레드</b>에서 받는다 — 요청 스레드도 부팅도 막지 않는다.
 * GPX 2,000 파일이라 분 단위로 걸릴 수 있다.
 *
 * <p>테스트·CI 에서는 프로퍼티로 꺼져 있어 이 빈 자체가 없다({@code LayerCatalogWiringTest}).
 */
@Component
@ConditionalOnProperty(prefix = "app.place.layer", name = "refresh-enabled", havingValue = "true")
public class LayerCatalogScheduler {

    private static final Logger log = LoggerFactory.getLogger(LayerCatalogScheduler.class);

    private final LayerCatalogService layers;
    private final LayerCatalogProperties properties;

    public LayerCatalogScheduler(LayerCatalogService layers, LayerCatalogProperties properties) {
        this.layers = layers;
        this.properties = properties;
    }

    @Scheduled(cron = "${app.place.layer.refresh-cron:0 20 5 1 * *}", zone = "Asia/Seoul")
    public void refreshMonthly() {
        try {
            layers.refreshAll();
        } catch (RuntimeException e) {
            // 스케줄 잡이 예외로 죽으면 다음 달에 아무도 그 사실을 모른다.
            log.error("공공데이터 레이어 적재가 예외로 끝났다", e);
        }
    }

    @EventListener(ApplicationReadyEvent.class)
    public void warmUpIfMissing() {
        if (!properties.isWarmUpOnStart()) {
            return;
        }
        boolean needed;
        try {
            needed = layers.needsRefresh();
        } catch (RuntimeException e) {
            log.warn("레이어 상태를 못 읽었다 — 기동 예열을 건너뛴다 ({})", e.getClass().getSimpleName());
            return;
        }
        if (!needed) {
            return;
        }
        Thread worker = new Thread(this::refreshMonthly, "place-layer-warmup");
        worker.setDaemon(true);
        worker.start();
        log.info("공공데이터 레이어가 없거나 낡았다 — 뒤에서 받는다");
    }
}
