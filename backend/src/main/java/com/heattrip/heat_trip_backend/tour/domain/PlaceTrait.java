package com.heattrip.heat_trip_backend.tour.domain;

import java.math.BigDecimal;

import jakarta.persistence.*;
import lombok.*;

/**
 * [place_traits] : CAT3(분류 코드)별 "고정 특성"을 저장.
 * - CSV를 앱 시작 시 1회 로드(비어있을 때만).
 * - 운영 중 거의 변하지 않는 데이터로 가정.
 */
// @Entity @Table(name = "place_traits")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceTrait {

    /** CAT3 코드가 PK. 예: "A02010400" */
    @Id
    @Column(name="place_id", length = 16, nullable = false)
    private String placeId;

    /** 분류명(한글). 예: "고택" */
    @Column(name="name", length = 200, nullable = false)
    private String name;

    /** PAD/성향 점수들 (없을 수 있으므로 Double/NULL 허용) */
    @Column(precision = 4, scale = 2) private BigDecimal pScore;
    @Column(precision = 4, scale = 2) private BigDecimal aScore;
    @Column(precision = 4, scale = 2) private BigDecimal dScore;
    @Column(precision = 4, scale = 2) private BigDecimal sociality;
    @Column(precision = 4, scale = 2) private BigDecimal noise;
    @Column(precision = 4, scale = 2) private BigDecimal crowdness;

    /** 필요 시 location_type 등 추가 가능 (지금 스냅샷 필수는 아님) */
}
