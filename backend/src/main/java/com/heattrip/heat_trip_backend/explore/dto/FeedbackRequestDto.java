// dto/FeedbackRequestDto.java
package com.heattrip.heat_trip_backend.explore.dto;

import lombok.*;
import jakarta.validation.constraints.*;
import java.time.LocalDateTime;
import java.util.Map;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class FeedbackRequestDto {
  @NotBlank private String beforeEmotion;
  @NotBlank private String afterEmotion;

  // {"sociality":0~1, ...}
  @NotNull private Map<String, @DecimalMin("0.0") @DecimalMax("1.0") Double> featureRatings;

  private String content;
  private LocalDateTime timestamp; // 클라이언트 측 시각(옵션)
}
