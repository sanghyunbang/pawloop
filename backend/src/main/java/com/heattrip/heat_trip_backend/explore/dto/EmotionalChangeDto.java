// dto/EmotionalChangeDto.java
package com.heattrip.heat_trip_backend.explore.dto;

import lombok.*;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class EmotionalChangeDto {
  private Double valence;
  private Double arousal;
  private Double dominance;
}
