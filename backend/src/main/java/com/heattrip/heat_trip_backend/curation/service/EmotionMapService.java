package com.heattrip.heat_trip_backend.curation.service;

import com.heattrip.heat_trip_backend.curation.dto.EmotionMapPlaceDTO;
import com.heattrip.heat_trip_backend.curation.entity.Place;
import com.heattrip.heat_trip_backend.curation.repository.CurationPlaceRepository;
import com.heattrip.heat_trip_backend.curation.ugc.UgcEmotionAggregationService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/**
 * F2-1: 감정 지도(emotion map) 조회 서비스.
 *
 * <p>주어진 (lat,lng) 근처에서 감정 데이터(seed/ugc)가 있는 장소만 골라
 * 각 핀의 대표 감정(dominantEmotion)과 함께 반환한다.
 *
 * <p>효율을 위해 1차로 바운딩 박스(mapy/mapx Between)로 후보를 좁힌 뒤,
 * 정확한 반경 컷은 Haversine 으로 다시 거르고 거리순 정렬 후 limit 로 자른다.
 *
 * <p>추천(recommend)/스코어링 경로와 분리되어 있으며 기존 흐름을 변경하지 않는다.
 */
@Service
@RequiredArgsConstructor
public class EmotionMapService {

    private static final double KM_PER_DEG_LAT = 111.0;

    private final CurationPlaceRepository placeRepo;

    /**
     * (lat,lng) 반경 radiusKm 안에서 감정 데이터가 있는 장소를 거리순으로 최대 limit 개 반환한다.
     *
     * @param lat      중심 위도
     * @param lng      중심 경도
     * @param radiusKm 반경(km)
     * @param limit    최대 반환 개수
     */
    @Transactional(readOnly = true)
    public List<EmotionMapPlaceDTO> findEmotionMapPlaces(double lat, double lng,
                                                         double radiusKm, int limit) {
        if (radiusKm <= 0 || limit <= 0) {
            return List.of();
        }

        // 1) 바운딩 박스 1차 필터 (전체 스캔 회피).
        double latDelta = radiusKm / KM_PER_DEG_LAT;
        // 고위도에서 0 으로 나누는 것을 방지하기 위해 cos 하한을 둔다.
        double cosLat = Math.max(Math.cos(Math.toRadians(lat)), 1e-6);
        double lngDelta = radiusKm / (KM_PER_DEG_LAT * cosLat);

        List<Place> candidates = placeRepo.findByMapyBetweenAndMapxBetween(
                lat - latDelta, lat + latDelta,
                lng - lngDelta, lng + lngDelta);

        // 2) Haversine 정확 반경 컷 + 감정 데이터 필터 + DTO 변환.
        List<Scored> scored = new ArrayList<>();
        for (Place p : candidates) {
            if (p == null || p.getMapy() == null || p.getMapx() == null) {
                continue;
            }
            double distKm = haversine(lat, lng, p.getMapy(), p.getMapx());
            if (distKm > radiusKm) {
                continue;
            }

            boolean exposable = UgcEmotionAggregationService.isUgcExposable(p);
            Map<String, Double> dist = exposable ? p.getUgcEmotion() : p.getSeedEmotion();
            if (dist == null || dist.isEmpty()) {
                // 감정 데이터 없음 -> 지도에 표시하지 않는다.
                continue;
            }
            String dominant = dominantEmotion(dist);
            if (dominant == null) {
                continue;
            }

            EmotionMapPlaceDTO dto = EmotionMapPlaceDTO.builder()
                    .placeId(p.getId())
                    .name(p.getTitle())
                    .lat(p.getMapy())
                    .lng(p.getMapx())
                    .cat3(p.getCat3())
                    .firstImageUrl(p.getFirstImage())
                    .dominantEmotion(dominant)
                    .emotion(dist)
                    .ugcCount(p.getUgcCount())
                    .exposable(exposable)
                    .build();
            scored.add(new Scored(distKm, dto));
        }

        // 3) 거리순 정렬 후 limit.
        return scored.stream()
                .sorted(Comparator.comparingDouble(Scored::distKm))
                .limit(limit)
                .map(Scored::dto)
                .toList();
    }

    /** 가중치가 가장 큰 감정 키를 반환한다. 빈 맵이면 null. */
    private static String dominantEmotion(Map<String, Double> dist) {
        String best = null;
        double bestW = Double.NEGATIVE_INFINITY;
        for (Map.Entry<String, Double> e : dist.entrySet()) {
            if (e.getKey() == null || e.getValue() == null) {
                continue;
            }
            if (e.getValue() > bestW) {
                bestW = e.getValue();
                best = e.getKey();
            }
        }
        return best;
    }

    /** ScoringService 와 동일한 Haversine 공식(km). */
    private static double haversine(double lat1, double lon1, double lat2, double lon2) {
        double R = 6371.0; // km
        double dLat = Math.toRadians(lat2 - lat1);
        double dLon = Math.toRadians(lon2 - lon1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                        Math.sin(dLon / 2) * Math.sin(dLon / 2);
        double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
        return R * c;
    }

    /** 거리+DTO 페어(정렬용 임시 보유). */
    private record Scored(double distKm, EmotionMapPlaceDTO dto) {}
}
