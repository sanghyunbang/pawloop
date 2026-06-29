package com.heattrip.heat_trip_backend.curation.controller;

import com.heattrip.heat_trip_backend.curation.dto.CategoryScoreDTO;
import com.heattrip.heat_trip_backend.curation.dto.EmotionMapPlaceDTO;
import com.heattrip.heat_trip_backend.curation.dto.PlaceScoreDTO;
import com.heattrip.heat_trip_backend.curation.dto.RankRequest;
import com.heattrip.heat_trip_backend.curation.dto.RecommendResultDto;
import com.heattrip.heat_trip_backend.curation.service.CurationRecommendService;
import com.heattrip.heat_trip_backend.curation.service.EmotionMapService;
import com.heattrip.heat_trip_backend.curation.service.PlaceSearchService;
import com.heattrip.heat_trip_backend.curation.service.ScoringService;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * curation 엔드포인트:
 * - /rank        : RankRequest(cat3Filter/거리 옵션 지원) 기반 랭킹
 * - /categories  : 감정 카테고리 집계
 * - /recommend   : LLM 라벨→CAT3→랭킹 (cat3Filter 없을 때만 LLM 호출)
 */
@Tag(name = "여행 추천 API", description = "사용자 감정(PAD) 기반의 장소 순위 및 카테고리 추천")
@RestController
@RequestMapping("api/curation")
@RequiredArgsConstructor
public class CurationController {

    private final ScoringService scoring;
    private final CurationRecommendService orchestration;
    private final EmotionMapService emotionMap;
    private final PlaceSearchService placeSearch;

    @PostMapping("/rank")
    public List<PlaceScoreDTO> rank(@RequestBody RankRequest req) {
        req.setTopK(50);
        req.setMaxDistanceKm(120.0);
        req.setDistanceWeight(0.2);
        return scoring.rank(req);
    }

    @PostMapping("/categories")
    public List<CategoryScoreDTO> categories(@RequestBody RankRequest req) {
        return scoring.categories(req);
    }

    @PostMapping("/recommend")
    public RecommendResultDto recommend(@RequestBody RankRequest req) {
        return orchestration.recommend(req);
    }

    /**
     * F2-1: 감정 지도(emotion map).
     * (lat,lng) 반경 안에서 감정 데이터(seed/ugc)가 있는 장소만 대표 감정과 함께 반환한다.
     */
    @GetMapping("/places/emotion-map")
    public List<EmotionMapPlaceDTO> emotionMap(
            @RequestParam double lat,
            @RequestParam double lng,
            @RequestParam(defaultValue = "5.0") double radiusKm,
            @RequestParam(defaultValue = "200") int limit) {
        return emotionMap.findEmotionMapPlaces(lat, lng, radiusKm, limit);
    }

    /**
     * F2-2: 탐색(discover/search).
     * 감정(mood) + 키워드(q)로 장소를 검색한다. 모든 파라미터 optional 이지만 mood/q 중 하나는 있어야
     * 의미 있는 결과가 나온다(둘 다 없으면 빈 리스트). 정렬: mood 있으면 moodScore desc → 거리 asc,
     * 없으면 거리 asc(위치 있을 때) 또는 title.
     */
    @GetMapping("/places/search")
    public List<EmotionMapPlaceDTO> searchPlaces(
            @RequestParam(required = false) String mood,
            @RequestParam(required = false) String q,
            @RequestParam(required = false) Double lat,
            @RequestParam(required = false) Double lng,
            @RequestParam(required = false) Double radiusKm,
            @RequestParam(defaultValue = "60") int limit) {
        return placeSearch.search(mood, q, lat, lng, radiusKm, limit);
    }
}
