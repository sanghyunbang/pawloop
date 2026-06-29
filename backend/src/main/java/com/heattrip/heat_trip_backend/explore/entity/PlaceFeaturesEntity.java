// entity/PlaceFeaturesEntity.java
package com.heattrip.heat_trip_backend.explore.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 기존에 "외부 import"로 채워지는 place_features 테이블 매핑.
 * 주의: 스키마상 PK가 link_id 이며, 실제 contentId와 동일하다고 가정합니다(주석 ①).
 */
@Data
@Entity
@Table(name = "place_features")
public class PlaceFeaturesEntity {

  @Id
  @Column(name = "link_id")
  private Long linkId;                       // = contentId 라고 가정(①)

  @Column(name = "n_reviews")
  private Integer nReviews;

  @Column(name = "n_blogs")
  private Integer nBlogs;

  // --------- 핵심 특성(0~1) ---------
  private Double sociality;
  private Double spirituality;
  private Double adventure;
  private Double culture;

  @Column(name = "nature_healing")
  private Double natureHealing;

  private Double quiet;

  // --------- 신뢰도(conf_*) ---------
  @Column(name = "conf_sociality")
  private Double confSociality;
  @Column(name = "conf_spirituality")
  private Double confSpirituality;
  @Column(name = "conf_adventure")
  private Double confAdventure;
  @Column(name = "conf_culture")
  private Double confCulture;
  @Column(name = "conf_nature_healing")
  private Double confNatureHealing;
  @Column(name = "conf_quiet")
  private Double confQuiet;

  @Column(name = "method_ver")
  private String methodVer;

  @Column(name = "updated_at")
  private LocalDateTime updatedAt;

  // --- getters/setters 생략 가능(Lombok 써도 OK) ---
  // ... (필요시 @Getter/@Setter)
  // (편의상 IDE의 Generate 기능을 추천)
}
