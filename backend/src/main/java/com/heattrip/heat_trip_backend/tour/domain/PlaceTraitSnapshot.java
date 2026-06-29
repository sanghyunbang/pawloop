// src/main/java/.../tour/domain/PlaceTraitSnapshot.java
package com.heattrip.heat_trip_backend.tour.domain;

import com.heattrip.heat_trip_backend.tour.support.StringListJsonConverter;
import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;
import java.util.List;

@Entity
@Table(name = "place_trait_snapshots")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceTraitSnapshot {

  @Id
  @Column(name = "cat3", length = 16)
  private String cat3;                   // ★ PK

  @Column(name = "cat3name")
  private String cat3Name;

  @Column(name = "p_score")   private Double pScore;
  @Column(name = "a_score")   private Double aScore;
  @Column(name = "d_score")   private Double dScore;
  @Column(name = "sociality") private Double sociality;
  @Column(name = "noise")     private Double noise;
  @Column(name = "crowdness") private Double crowdness;

  @Lob @Column(name = "hashtags")
  @Convert(converter = StringListJsonConverter.class)
  private List<String> hashtags;

  @Lob @Column(name = "simple_tags")
  @Convert(converter = StringListJsonConverter.class)
  private List<String> simpleTags;

  @Lob @Column(name = "short_desc1")
  private String shortDesc1;

  @Lob @Column(name = "short_desc2")
  private String shortDesc2;

  @Column(name = "snapshot_at")
  private LocalDateTime snapshotAt;
}
