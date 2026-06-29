package com.heattrip.heat_trip_backend.curation.entity;

import java.util.Map;

import jakarta.persistence.Column;
import jakarta.persistence.Convert;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.Table;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/**
 * places 테이블 매핑
 * - PK: contentid (BIGINT)
 */
@Entity(name = "CurationPlace")
@Table(name = "places")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class Place {

    @Id
    @Column(name = "contentid", nullable = false)
    private Long id;

    @Column(name = "title")
    private String title;

    /** 세부 카테고리 코드(CAT3) */
    @Column(name = "cat3")
    private String cat3;

    /** 위경도(가정: mapy=lat, mapx=lon) */
    @Column(name = "mapx")
    private Double mapx;

    @Column(name = "mapy")
    private Double mapy;

    @Column(name = "firstimage")
    private String firstImage;

    /**
     * 시드 감정 분포(감정→가중치). 공공데이터 + LLM 1회 배치로 생성되며 이후 고정.
     * 예) {"평온":0.4,"설렘":0.3}. nullable.
     * Phase 2 UGC 집계 전까지의 기본 노출 대상.
     */
    @Lob
    @Convert(converter = EmotionWeightMapJsonConverter.class)
    @Column(name = "seed_emotion", columnDefinition = "json")
    private Map<String, Double> seedEmotion;

    /**
     * UGC 감정 분포(감정→가중치). 사용자 다이어리 기분에서 집계. nullable.
     * 재식별 방지를 위해 {@link #ugcCount} &lt; 5 인 경우 노출하지 않는다(노출 로직은 본 티켓 범위 밖).
     */
    @Lob
    @Convert(converter = EmotionWeightMapJsonConverter.class)
    @Column(name = "ugc_emotion", columnDefinition = "json")
    private Map<String, Double> ugcEmotion;

    /** UGC 데이터포인트 수. 기본값 0. 5 미만이면 seed_emotion만 노출(가드 로직은 본 티켓 범위 밖). */
    @Builder.Default
    @Column(name = "ugc_count", nullable = false)
    private int ugcCount = 0;
}
