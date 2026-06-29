package com.heattrip.heat_trip_backend.curation.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** 단일 장소 점수(설명용으로 trait/popularity/final 분리) */
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class PlaceScoreDTO {
    private Long placeId;
    private String name;
    private String cat3Code;
    private double traitMatch;
    private double popularity;
    private double finalScore;

    // (선택) 거리 응답도 원하면 노출
    private Double distanceKm;
    private Double distanceScore;

    // (추가)
    // 사진관련
    private String firstImageUrl;
    // 카테고리 이름
    private String cat3Name;

    // (B2-3, 디버깅용) 감정 적합도. 감정 신호가 없으면 null. nullable 이므로 기존 JSON 소비자 호환.
    private Double emotionFit;
}
