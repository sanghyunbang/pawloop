package com.heattrip.heat_trip_backend.curation.seed;

import com.heattrip.heat_trip_backend.curation.entity.Place;
import com.heattrip.heat_trip_backend.curation.repository.CurationPlaceRepository;
import com.heattrip.heat_trip_backend.curation.service.Cat3DictionaryService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.util.Map;

/**
 * B2-1: 장소별 {@code seed_emotion} 분포를 1회/멱등 배치로 생성한다.
 *
 * <p>각 장소의 cat3(코드)를 사람이 읽을 수 있는 카테고리 라벨로 변환해
 * Python {@code POST /seed-emotion}을 호출하고, 결과 맵을 {@code place.seedEmotion}에 저장한다.
 *
 * <p>추천(recommend) 경로에서는 절대 호출하지 않는다 — 오프라인 배치 전용.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class SeedEmotionBatchService {

    private static final int PAGE_SIZE = 100;
    /** 호출 간 가벼운 레이트리밋(ms). 0이면 슬립 없음. */
    private static final long SLEEP_BETWEEN_CALLS_MS = 50L;

    private final CurationPlaceRepository placeRepository;
    private final Cat3DictionaryService cat3Dictionary;
    private final SeedEmotionClient seedEmotionClient;

    /**
     * 전체 장소에 대해 seed_emotion 을 생성/저장한다.
     *
     * @param overwrite true 면 이미 값이 있어도 다시 생성, false 면 {@code seedEmotion == null} 인 것만.
     * @return 실제로 업데이트(저장)된 장소 수
     */
    public int seedAll(boolean overwrite) {
        int updated = 0;
        int pageIndex = 0;

        while (true) {
            // overwrite 모드는 전체를 페이지 단위로 순회한다.
            // 비-overwrite 모드는 갱신될 때마다 null 집합이 줄어들므로 항상 첫 페이지를 다시 읽는다.
            // (단, 한 건도 갱신되지 않은 페이지가 나오면 더 진행할 게 없으므로 종료한다.)
            int requestPage = overwrite ? pageIndex : 0;
            Pageable pageable = PageRequest.of(requestPage, PAGE_SIZE);

            Page<Place> page = overwrite
                    ? placeRepository.findAll(pageable)
                    : placeRepository.findBySeedEmotionIsNull(pageable);

            if (page.isEmpty()) {
                break;
            }

            int updatedThisPage = 0;
            for (Place place : page.getContent()) {
                if (!overwrite && place.getSeedEmotion() != null) {
                    continue;
                }
                if (processOne(place)) {
                    updated++;
                    updatedThisPage++;
                }
                sleepQuietly();
            }

            if (overwrite) {
                if (!page.hasNext()) {
                    break;
                }
                pageIndex++;
            } else {
                // 무한 루프 방지: null 인 행만 다시 읽는데 한 건도 갱신 못 했다면
                // 남은 행은 모두 (오류/스킵으로) 갱신 불가이므로 종료한다.
                if (updatedThisPage == 0) {
                    break;
                }
            }
        }

        log.info("[SEED] batch finished. overwrite={}, updated={}", overwrite, updated);
        return updated;
    }

    /**
     * 단일 장소 처리. 오류는 로깅 후 삼키고 계속 진행한다(배치 전체 중단 방지).
     *
     * @return 저장 성공 시 true
     */
    private boolean processOne(Place place) {
        try {
            String category = resolveCategoryLabel(place);
            if (category == null || category.isBlank()) {
                log.warn("[SEED] skip place id={} : no resolvable category (cat3={})",
                        place.getId(), place.getCat3());
                return false;
            }

            // intro 텍스트는 현재 엔티티에 없으므로 null 로 전달한다.
            Map<String, Double> emotion = seedEmotionClient.fetchSeedEmotion(category, null);
            if (emotion == null || emotion.isEmpty()) {
                log.warn("[SEED] empty response for place id={} (category={})", place.getId(), category);
                return false;
            }

            place.setSeedEmotion(emotion);
            placeRepository.save(place);
            log.debug("[SEED] place id={} category='{}' -> {}", place.getId(), category, emotion);
            return true;
        } catch (Exception e) {
            log.error("[SEED] failed place id={} (cat3={}): {}",
                    place.getId(), place.getCat3(), e.toString());
            return false;
        }
    }

    /** cat3 코드를 한글 대표명으로 변환. 사전에 없으면 raw 코드를 그대로 사용. */
    private String resolveCategoryLabel(Place place) {
        String code = place.getCat3();
        if (code == null || code.isBlank()) {
            return null;
        }
        String name = cat3Dictionary.getNameForCat3(code);
        return (name != null && !name.isBlank()) ? name : code;
    }

    private void sleepQuietly() {
        if (SLEEP_BETWEEN_CALLS_MS <= 0) {
            return;
        }
        try {
            Thread.sleep(SLEEP_BETWEEN_CALLS_MS);
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
        }
    }
}
