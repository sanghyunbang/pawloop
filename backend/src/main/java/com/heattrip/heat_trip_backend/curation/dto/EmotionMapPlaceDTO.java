package com.heattrip.heat_trip_backend.curation.dto;

import java.util.Map;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * F2-1: 감정 지도(emotion map) 핀 1개를 표현하는 DTO.
 * 감정 데이터(seed/ugc)가 있는 장소만 반환되며, 클라이언트는 {@link #dominantEmotion} 으로 핀 색을 칠한다.
 */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class EmotionMapPlaceDTO {
    /** places.contentid */
    private Long placeId;
    /** places.title */
    private String name;
    /** places.mapy (위도) */
    private Double lat;
    /** places.mapx (경도) */
    private Double lng;
    /** places.cat3 */
    private String cat3;
    /** places.firstimage */
    private String firstImageUrl;
    /** 가중치가 가장 큰 감정 키(SSOT 한글 키). 핀 색 결정용. */
    private String dominantEmotion;
    /** 실제 사용된 감정 분포(ugc 또는 seed). */
    private Map<String, Double> emotion;
    /** places.ugc_count */
    private int ugcCount;
    /** ugc_emotion 노출 가능 여부(true=ugc 사용, false=seed 사용). */
    private boolean exposable;
    /**
     * 사용자 위치(lat,lng)가 주어졌을 때의 Haversine 거리(km). 위치 미제공 시 null.
     * /places/search 전용 필드이며 /places/emotion-map 응답에서는 null 로 둔다(기존 소비자 호환).
     */
    private Double distanceKm;
    /**
     * mood 필터가 주어졌을 때 해당 무드의 분포 가중치(dist.getOrDefault(mood,0)). mood 미제공 시 null.
     * /places/search 전용 필드.
     */
    private Double moodScore;
}
