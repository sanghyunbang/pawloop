// dto/EmotionalReviewDto.java
package com.heattrip.heat_trip_backend.explore.dto;

import lombok.*;

import java.time.LocalDateTime;
import java.util.List;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class EmotionalReviewDto {
  private String id;                  // 문자열화
  private String author;
  private LocalDateTime date;         // review_date
  private String beforeEmotion;
  private String afterEmotion;
  private EmotionalChangeDto emotionalChange;
  private String content;
  private Integer helpfulCount;
  private List<String> images;
}
