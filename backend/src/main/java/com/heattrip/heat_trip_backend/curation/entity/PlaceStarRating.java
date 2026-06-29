package com.heattrip.heat_trip_backend.curation.entity;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * place_star_ratings 매핑
 * - PK: link_id (단일 PK)  ← 스크린샷 구조에 맞춤
 * - rating: 1..5 범위(장소 평균 별점으로 이해)
 * - source: 수집 출처(옵션; 단일 PK 구조여도 평균을 한 행으로 보관한다고 가정)
 */
@Entity
@Table(name = "place_star_ratings")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceStarRating {

    /** places.contentid와 동일 키 */
    @Id
    @Column(name = "link_id", nullable = false)
    private Long linkId;

    /** 평균 별점(1..5 가정) */
    @Column(name = "rating")
    private Double rating;

    /** 데이터 출처(옵션) */
    @Column(name = "source")
    private String source;

    /** 업데이트 시각(옵션) */
    @Column(name = "updated_at")
    private LocalDateTime updatedAt;
}
