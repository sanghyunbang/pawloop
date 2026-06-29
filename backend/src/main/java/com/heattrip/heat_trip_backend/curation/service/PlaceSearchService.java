package com.heattrip.heat_trip_backend.curation.service;

import com.heattrip.heat_trip_backend.curation.dto.EmotionMapPlaceDTO;
import com.heattrip.heat_trip_backend.curation.entity.Place;
import com.heattrip.heat_trip_backend.curation.repository.CurationPlaceRepository;
import com.heattrip.heat_trip_backend.curation.ugc.UgcEmotionAggregationService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Map;

/**
 * F2-2: 탐색(discover/search) 서비스.
 *
 * <p>Flutter "탐색" 화면을 위해 감정(mood) + 키워드(q) 로 장소를 검색한다.
 *
 * <p>후보 집합 구성:
 * <ul>
 *   <li>q 가 있으면 title LIKE %q% 인 장소(파라미터 바인딩으로 인젝션 회피).</li>
 *   <li>q 가 없고 mood 만 있으면 감정 데이터(seed/ugc)가 있는 장소만. 전체 테이블 스캔을 막기 위해
 *       lat/lng 가 있으면 {@link EmotionMapService} 와 동일한 바운딩 박스로, 없으면 하드 캡으로 좁힌다.</li>
 * </ul>
 *
 * <p>각 후보의 감정 분포는 {@code isUgcExposable ? ugcEmotion : seedEmotion} 로 선택하며,
 * mood 필터/거리/정렬은 {@link #search} 의 문서 주석을 참고한다.
 *
 * <p>추천(recommend)/스코어링 경로와 완전히 분리되어 있으며 기존 흐름을 변경하지 않는다.
 */
@Service
@RequiredArgsConstructor
public class PlaceSearchService {

    private static final double KM_PER_DEG_LAT = 111.0;

    /** q 없이 mood 만 주어졌을 때, 위치도 없을 경우 끌어올 감정 장소의 하드 캡(전체 스캔 회피). */
    private static final int NO_LOCATION_CANDIDATE_CAP = 500;

    /** q LIKE 검색 시 후보를 가져올 최대 행 수(전체 스캔 회피). limit 보다 넉넉하게 둔다. */
    private static final int LIKE_CANDIDATE_CAP = 1000;

    /** 위치가 있고 radiusKm 미지정 시, 바운딩 박스 후보 축소에 사용할 기본 반경(km). */
    private static final double DEFAULT_BOX_RADIUS_KM = 20.0;

    private final CurationPlaceRepository placeRepo;

    /**
     * mood + q 로 장소를 검색해 정렬된 DTO 리스트를 반환한다.
     *
     * <p><b>후보 집합</b>
     * <ul>
     *   <li>q 가 있으면 title LIKE %q% (캡 {@value #LIKE_CANDIDATE_CAP}).</li>
     *   <li>q 가 없고 mood 가 있으면 감정 데이터가 있는 장소: lat/lng 있으면 바운딩 박스,
     *       없으면 하드 캡({@value #NO_LOCATION_CANDIDATE_CAP}).</li>
     *   <li>q/mood 둘 다 없으면 빈 리스트.</li>
     * </ul>
     *
     * <p><b>감정 분포</b> dist = isUgcExposable ? ugcEmotion : seedEmotion. dominantEmotion = argmax(dist) (없으면 null).
     *
     * <p><b>mood 필터</b> mood 가 있으면 moodScore = dist.getOrDefault(mood,0).
     * 감정 데이터가 없는 장소는 q 가 매칭됐을 때만 포함(moodScore=0).
     * dist 에 mood 가 weight&gt;0 으로 들어있는 장소를 선호한다(정렬에서 자연 반영).
     *
     * <p><b>거리</b> lat/lng 있으면 Haversine distanceKm 계산. radiusKm 있으면 그 안만 통과.
     *
     * <p><b>정렬</b> mood 있으면 moodScore desc, 거리 asc; 없으면 거리 asc(위치 있을 때) 또는 title.
     * 마지막에 limit 로 자른다.
     *
     * @param mood     SSOT 한글 무드 키(기쁨/슬픔/불안/분노/평온/설렘). null/blank 허용.
     * @param q        키워드(title LIKE). null/blank 허용.
     * @param lat      사용자 위도(거리/박스용). null 허용.
     * @param lng      사용자 경도(거리/박스용). null 허용.
     * @param radiusKm 반경 컷(km). null = 반경 제한 없음.
     * @param limit    최대 반환 개수.
     */
    @Transactional(readOnly = true)
    public List<EmotionMapPlaceDTO> search(String mood, String q,
                                           Double lat, Double lng,
                                           Double radiusKm, int limit) {
        if (limit <= 0) {
            return List.of();
        }
        boolean hasMood = StringUtils.hasText(mood);
        boolean hasQ = StringUtils.hasText(q);
        if (!hasMood && !hasQ) {
            // 검색 조건이 전혀 없으면 전체 테이블을 끌어오지 않는다.
            return List.of();
        }
        boolean hasLocation = (lat != null && lng != null);

        // 1) 후보 집합 구성.
        List<Place> candidates;
        if (hasQ) {
            candidates = placeRepo.findByTitleContaining(q.trim(), PageRequest.of(0, LIKE_CANDIDATE_CAP));
        } else {
            // mood 만 있는 경우: 감정 데이터가 있는 장소만.
            candidates = emotionalCandidates(lat, lng, radiusKm, hasLocation);
        }

        // 2) 각 후보를 DTO 로 변환하면서 mood/거리 필터 적용.
        List<EmotionMapPlaceDTO> result = new ArrayList<>();
        for (Place p : candidates) {
            if (p == null) {
                continue;
            }

            // 감정 분포 선택(EmotionMapService 와 동일 규칙).
            boolean exposable = UgcEmotionAggregationService.isUgcExposable(p);
            Map<String, Double> dist = exposable ? p.getUgcEmotion() : p.getSeedEmotion();
            boolean hasDist = (dist != null && !dist.isEmpty());
            String dominant = hasDist ? dominantEmotion(dist) : null;

            // mood 필터: 감정 데이터 없는 장소는 q 매칭됐을 때만 포함(moodScore=0).
            Double moodScore = null;
            if (hasMood) {
                if (!hasDist) {
                    if (!hasQ) {
                        continue; // 감정 데이터 없음 + q 없음 -> 제외.
                    }
                    moodScore = 0.0; // q 매칭으로 포함하되 점수는 0.
                } else {
                    moodScore = dist.getOrDefault(mood, 0.0);
                }
            }

            // 거리 + 반경 컷.
            Double distanceKm = null;
            if (hasLocation && p.getMapy() != null && p.getMapx() != null) {
                distanceKm = haversine(lat, lng, p.getMapy(), p.getMapx());
                if (radiusKm != null && distanceKm > radiusKm) {
                    continue;
                }
            }

            result.add(EmotionMapPlaceDTO.builder()
                    .placeId(p.getId())
                    .name(p.getTitle())
                    .lat(p.getMapy())
                    .lng(p.getMapx())
                    .cat3(p.getCat3())
                    .firstImageUrl(p.getFirstImage())
                    .dominantEmotion(dominant)
                    .emotion(hasDist ? dist : null)
                    .ugcCount(p.getUgcCount())
                    .exposable(exposable)
                    .distanceKm(distanceKm)
                    .moodScore(moodScore)
                    .build());
        }

        // 3) 정렬 + limit.
        sort(result, hasMood, hasLocation);
        return result.stream().limit(limit).toList();
    }

    /** q 가 없고 mood 만 있을 때의 후보: 감정 데이터가 있는 장소(박스 또는 하드 캡). */
    private List<Place> emotionalCandidates(Double lat, Double lng, Double radiusKm, boolean hasLocation) {
        if (hasLocation) {
            double boxRadius = (radiusKm != null && radiusKm > 0) ? radiusKm : DEFAULT_BOX_RADIUS_KM;
            double latDelta = boxRadius / KM_PER_DEG_LAT;
            double cosLat = Math.max(Math.cos(Math.toRadians(lat)), 1e-6);
            double lngDelta = boxRadius / (KM_PER_DEG_LAT * cosLat);
            return placeRepo.findEmotionalInBox(
                    lat - latDelta, lat + latDelta,
                    lng - lngDelta, lng + lngDelta);
        }
        // 위치 없음 -> 전체 스캔 회피를 위해 하드 캡.
        Pageable cap = PageRequest.of(0, NO_LOCATION_CANDIDATE_CAP);
        return placeRepo.findEmotionalCapped(cap);
    }

    /** 정렬: mood 있으면 moodScore desc -> 거리 asc; 없으면 거리 asc(위치 있을 때) 또는 title asc. */
    private static void sort(List<EmotionMapPlaceDTO> list, boolean hasMood, boolean hasLocation) {
        if (hasMood) {
            list.sort(Comparator
                    .comparingDouble((EmotionMapPlaceDTO d) -> nz(d.getMoodScore())).reversed()
                    .thenComparing(Comparator.comparingDouble(PlaceSearchService::distOrMax)));
        } else if (hasLocation) {
            list.sort(Comparator.comparingDouble(PlaceSearchService::distOrMax));
        } else {
            list.sort(Comparator.comparing(d -> d.getName() == null ? "" : d.getName()));
        }
    }

    /** 거리 정렬용: 거리 미상(null)은 맨 뒤로 보낸다. */
    private static double distOrMax(EmotionMapPlaceDTO d) {
        return d.getDistanceKm() == null ? Double.MAX_VALUE : d.getDistanceKm();
    }

    private static double nz(Double v) {
        return v == null ? 0.0 : v;
    }

    /** 가중치가 가장 큰 감정 키를 반환한다. 빈 맵이면 null. (EmotionMapService 와 동일 로직) */
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

    /** ScoringService/EmotionMapService 와 동일한 Haversine 공식(km). */
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
}
