// src/main/java/com/heattrip/heat_trip_backend/curation/entity/PlaceTrait.java
package com.heattrip.heat_trip_backend.curation.entity;

import jakarta.persistence.*;
import lombok.*;

@Entity
@Table(name = "place_traits")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceTrait {
    @Id
    @Column(name="place_id", length=16, nullable=false)
    private String placeId;

    @Column(name="name", length=200, nullable=false)
    private String name;

    // ★ 반드시 컬럼명 지정(스네이크케이스). 중복/충돌 방지
    @Column(name="p_score")  private Double pScore;
    @Column(name="a_score")  private Double aScore;
    @Column(name="d_score")  private Double dScore;
    @Column(name="sociality") private Double sociality;
    @Column(name="noise")     private Double noise;
    @Column(name="crowdness") private Double crowdness;

    @Column(name="del_state")     private Integer delState;
    @Column(name="location_type") private String locationType;

    @Column(name="hash1") private String hash1;
    @Column(name="hash2") private String hash2;
    @Column(name="hash3") private String hash3;

    @Column(name="simple_tag1") private String simpleTag1;
    @Column(name="simple_tag2") private String simpleTag2;
    @Column(name="simple_tag3") private String simpleTag3;

    @Column(name="short_descript1") private String shortDescript1;
    @Column(name="short_descript2") private String shortDescript2;
}
