// entity/EmotionFeedbackEntity.java
package com.heattrip.heat_trip_backend.explore.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "emotion_feedbacks")
public class EmotionFeedbackEntity {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "content_id", nullable = false)
  private Long contentId;

  @Column(name = "before_emotion", nullable = false, length = 32)
  private String beforeEmotion;

  @Column(name = "after_emotion", nullable = false, length = 32)
  private String afterEmotion;

  @Lob
  @Column(name = "feature_ratings_json")
  private String featureRatingsJson; // {"sociality":0.8,...} (주석 ③)

  @Lob
  private String content;

  @Column(name = "client_timestamp")
  private LocalDateTime clientTimestamp;

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt = LocalDateTime.now();

  // getters/setters ...
}
