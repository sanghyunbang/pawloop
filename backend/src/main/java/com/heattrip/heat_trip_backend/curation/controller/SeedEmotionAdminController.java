package com.heattrip.heat_trip_backend.curation.controller;

import com.heattrip.heat_trip_backend.curation.seed.SeedEmotionBatchService;
import com.heattrip.heat_trip_backend.curation.ugc.UgcEmotionAggregationService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * B2-1: seed_emotion 배치 트리거 (내부/관리자용).
 *
 * <p>추천 경로와 무관한 오프라인 배치다. 1회/멱등 실행을 위한 수동 트리거 엔드포인트.
 */
@Slf4j
@Tag(name = "Curation Admin", description = "큐레이션 내부/배치 관리 API")
@RestController
@RequestMapping("api/curation/admin")
@RequiredArgsConstructor
public class SeedEmotionAdminController {

    private final SeedEmotionBatchService seedEmotionBatchService;
    private final UgcEmotionAggregationService ugcEmotionAggregationService;

    /**
     * 장소별 seed_emotion 분포를 생성/저장하는 배치를 실행한다.
     *
     * @param overwrite false(기본): seed_emotion 이 비어있는 장소만, true: 전체 재생성
     * @return {@code {"updated": <건수>, "overwrite": <bool>}}
     */
    @Operation(summary = "seed_emotion 배치 실행", description = "각 장소의 cat3 → Python /seed-emotion 호출로 감정 분포를 생성한다.")
    @PostMapping("/seed-emotions")
    public Map<String, Object> seedEmotions(
            @RequestParam(name = "overwrite", defaultValue = "false") boolean overwrite) {
        log.info("[SEED] admin trigger: seed-emotions overwrite={}", overwrite);
        int updated = seedEmotionBatchService.seedAll(overwrite);
        return Map.of("updated", updated, "overwrite", overwrite);
    }

    /**
     * B2-2: 다이어리 기분을 장소별로 집계해 ugc_emotion/ugc_count 를 재계산/저장한다.
     *
     * <p>현재 다이어리 전체에서 재계산하므로 삭제분도 자연 반영된다(B2-4).
     *
     * @return {@code {"updated": <갱신된 장소 수>}}
     */
    @Operation(summary = "ugc_emotion 집계 실행",
            description = "placeId 가 있는 다이어리의 기분을 장소별로 집계해 ugc_emotion/ugc_count 를 재계산한다(recompute).")
    @PostMapping("/aggregate-ugc-emotions")
    public Map<String, Object> aggregateUgcEmotions() {
        log.info("[UGC] admin trigger: aggregate-ugc-emotions");
        int updated = ugcEmotionAggregationService.recomputeAll();
        return Map.of("updated", updated);
    }
}
