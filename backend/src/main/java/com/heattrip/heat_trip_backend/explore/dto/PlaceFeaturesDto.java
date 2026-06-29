// dto/PlaceFeaturesDto.java
package com.heattrip.heat_trip_backend.explore.dto;

import lombok.*;

import java.time.LocalDateTime;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class PlaceFeaturesDto {
  // 핵심 값(0~1)
  private Double sociality;
  private Double spirituality;
  private Double adventure;
  private Double culture;
  private Double nature_healing; // 프론트가 snake_case를 기대(주석 ④)
  private Double quiet;

  // (옵션) 신뢰도/메타
  private Integer n_reviews;
  private Integer n_blogs;
  private Double conf_sociality;
  private Double conf_spirituality;
  private Double conf_adventure;
  private Double conf_culture;
  private Double conf_nature_healing;
  private Double conf_quiet;
  private String method_ver;
  private LocalDateTime updated_at;
}
