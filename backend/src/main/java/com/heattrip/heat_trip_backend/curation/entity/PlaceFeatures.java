package com.heattrip.heat_trip_backend.curation.entity;

import jakarta.persistence.*;
import lombok.*;

/**
 * place_features 테이블 매핑
 * - link_id == places.contentid
 * - feature(−1..1) → 서비스에서 0..1로 변환해 사용
 * - conf_*: 0..1 (증거 신뢰도), n_reviews/n_blogs: 볼륨 계산에 활용
 */
@Entity(name = "CurationPlaceFeatures")
@Table(name = "place_features")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceFeatures {

    /** FK(=PK): places.contentid와 동일 */
    @Id
    @Column(name = "link_id", nullable = false)
    private Long placeId;

    @Column(name = "n_reviews") private Integer nReviews;
    @Column(name = "n_blogs")   private Integer nBlogs;

    @Column(name = "sociality")      private Double sociality;        // −1..1
    @Column(name = "spirituality")   private Double spirituality;     // −1..1
    @Column(name = "adventure")      private Double adventure;        // −1..1
    @Column(name = "culture")        private Double culture;          // −1..1
    @Column(name = "nature_healing") private Double natureHealing;    // −1..1
    @Column(name = "quiet")          private Double quiet;            // −1..1

    @Column(name = "conf_sociality")      private Double confSociality;       // 0..1
    @Column(name = "conf_spirituality")   private Double confSpirituality;    // 0..1
    @Column(name = "conf_adventure")      private Double confAdventure;       // 0..1
    @Column(name = "conf_culture")        private Double confCulture;         // 0..1
    @Column(name = "conf_nature_healing") private Double confNatureHealing;   // 0..1
    @Column(name = "conf_quiet")          private Double confQuiet;           // 0..1
}
