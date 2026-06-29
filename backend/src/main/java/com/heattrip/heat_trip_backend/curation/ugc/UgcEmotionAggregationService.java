package com.heattrip.heat_trip_backend.curation.ugc;

import com.heattrip.heat_trip_backend.curation.entity.Place;
import com.heattrip.heat_trip_backend.curation.mood.MoodPadPreset;
import com.heattrip.heat_trip_backend.curation.repository.CurationPlaceRepository;
import com.heattrip.heat_trip_backend.schedules.entity.Journey;
import com.heattrip.heat_trip_backend.schedules.repository.JourneyRepository_v2;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * B2-2: 사용자 다이어리의 기분(moodLabel)을 장소(placeId)별로 집계해
 * {@code places.ugc_emotion}(6개 무드 키에 대한 정규화 분포)과 {@code places.ugc_count}에 저장한다.
 *
 * <p><b>재계산(recompute) 방식:</b> 매 실행마다 현재 다이어리 전체를 다시 읽어 처음부터 집계한다.
 * 따라서 다이어리를 삭제한 뒤 다시 실행하면 그 기여분이 자연스럽게 사라진다 —
 * 이는 별도 코드 없이 <b>B2-4(다이어리 삭제가 집계에 반영)</b>를 만족한다.
 *
 * <p><b>재식별 방지 가드(노출 규칙):</b> 집계는 ugc_count/ugc_emotion 을 항상 저장한다.
 * "ugc_count &lt; 5 이면 ugc_emotion 을 노출하지 않고 seed 로 폴백"하는 것은 <b>읽기/노출</b> 시점의 규칙이며,
 * 본 서비스의 저장 단계에서는 적용하지 않는다. UI/B2-3 가 사용할 수 있도록
 * {@link #isUgcExposable(Place)} 헬퍼(count &gt;= 5)를 제공한다.
 *
 * <p>추천(recommend) 경로에서는 절대 호출하지 않는다 — 오프라인/관리자 배치 전용.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class UgcEmotionAggregationService {

    /** 재식별 방지: ugc_emotion 을 노출하려면 최소 이만큼의 데이터포인트가 필요하다. */
    public static final int MIN_EXPOSABLE_UGC_COUNT = 5;

    private static final int PAGE_SIZE = 500;

    private final JourneyRepository_v2 journeyRepository;
    private final CurationPlaceRepository placeRepository;

    /**
     * 전체 다이어리에서 장소별 UGC 감정 분포를 재계산해 저장한다.
     *
     * <p>placeId 가 있고 moodLabel 이 SSOT 6개 키 중 하나인 다이어리만 집계한다.
     * 장소별로 각 무드 키의 빈도를 세고, 합이 1.0 이 되도록 정규화한 분포를 ugcEmotion 에,
     * 유효 데이터포인트 총수를 ugcCount 에 저장한다.
     *
     * @return 실제로 갱신(저장)된 장소 수
     */
    public int recomputeAll() {
        // 1) 현재 다이어리 전체를 페이지 단위로 읽어 placeId -> (moodKey -> count) 로 집계.
        Map<Long, Map<String, Integer>> tallyByPlace = new HashMap<>();
        int pageIndex = 0;
        while (true) {
            Pageable pageable = PageRequest.of(pageIndex, PAGE_SIZE);
            Page<Journey> page = journeyRepository.findForUgcAggregation(pageable);
            for (Journey j : page.getContent()) {
                Long placeId = j.getPlaceId();
                String mood = j.getMoodLabel();
                if (placeId == null || mood == null) {
                    continue;
                }
                // SSOT 집합에 없는 moodLabel 은 무시한다.
                if (!MoodPadPreset.MOOD_KEYS.contains(mood)) {
                    continue;
                }
                tallyByPlace
                        .computeIfAbsent(placeId, k -> new HashMap<>())
                        .merge(mood, 1, Integer::sum);
            }
            if (!page.hasNext()) {
                break;
            }
            pageIndex++;
        }

        // 2) 집계된 각 장소를 로드해 정규화 분포 + count 를 저장. 장소별 오류는 로깅 후 스킵.
        int updated = 0;
        for (Map.Entry<Long, Map<String, Integer>> entry : tallyByPlace.entrySet()) {
            Long placeId = entry.getKey();
            Map<String, Integer> counts = entry.getValue();
            try {
                int total = counts.values().stream().mapToInt(Integer::intValue).sum();
                if (total <= 0) {
                    continue; // 유효 데이터포인트 없음 -> 그대로 둔다.
                }
                Place place = placeRepository.findById(placeId).orElse(null);
                if (place == null) {
                    log.warn("[UGC] skip placeId={} : place not found", placeId);
                    continue;
                }
                Map<String, Double> distribution = normalize(counts, total);
                place.setUgcEmotion(distribution);
                place.setUgcCount(total);
                placeRepository.save(place);
                updated++;
                log.debug("[UGC] placeId={} count={} -> {}", placeId, total, distribution);
            } catch (Exception e) {
                log.error("[UGC] failed placeId={} : {}", placeId, e.toString());
            }
        }

        log.info("[UGC] recompute finished. placesUpdated={}", updated);
        return updated;
    }

    /**
     * 재식별 방지 노출 가드. ugc_count 가 임계치(5) 이상일 때만 ugc_emotion 노출을 허용한다.
     * 저장 단계가 아니라 읽기/노출(UI, B2-3) 단계에서 사용해야 한다.
     */
    public static boolean isUgcExposable(Place place) {
        return place != null && place.getUgcCount() >= MIN_EXPOSABLE_UGC_COUNT;
    }

    /** 무드 빈도 맵을 합이 1.0 이 되는 분포로 정규화한다. */
    private Map<String, Double> normalize(Map<String, Integer> counts, int total) {
        Map<String, Double> dist = new LinkedHashMap<>();
        for (Map.Entry<String, Integer> e : counts.entrySet()) {
            dist.put(e.getKey(), e.getValue() / (double) total);
        }
        return dist;
    }
}
