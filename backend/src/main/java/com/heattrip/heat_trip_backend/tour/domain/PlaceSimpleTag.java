package com.heattrip.heat_trip_backend.tour.domain;

import jakarta.persistence.*;
import lombok.*;

/**
 * [place_simple_tags] : CAT3별 심플 태그를 "행 단위"로 저장.
 * - 예: 전통, 감성, 산책
 */
@Entity @Table(name = "place_simple_tags",
        indexes = { @Index(name="idx_pst_place", columnList = "place_id"),
                    @Index(name="idx_pst_tag", columnList = "tag") })
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceSimpleTag {
    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /** CAT3 코드 */
    @Column(name="place_id", length = 16, nullable = false)
    private String placeId;

    /** '전통', '감성' 등 */
    @Column(name="tag", length = 100, nullable = false)
    private String tag;
}
