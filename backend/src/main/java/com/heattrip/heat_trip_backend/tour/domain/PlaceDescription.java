package com.heattrip.heat_trip_backend.tour.domain;

import jakarta.persistence.*;
import lombok.*;

/**
 * [place_descriptions] : CAT3별 설명 문장(두 줄)을 저장.
 */
@Entity @Table(name = "place_descriptions")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceDescription {

    /** CAT3가 PK (place_traits와 1:1 가정) */
    @Id
    @Column(name="place_id", length = 16, nullable = false)
    private String placeId;

    @Lob @Column(name="short_desc_1")
    private String shortDesc1;

    @Lob @Column(name="short_desc_2")
    private String shortDesc2;
}
