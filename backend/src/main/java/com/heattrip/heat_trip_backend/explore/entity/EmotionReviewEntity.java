// entity/EmotionReviewEntity.java
package com.heattrip.heat_trip_backend.explore.entity;

import jakarta.persistence.*;
import lombok.Data;

import java.time.LocalDateTime;

@Data
@Entity
@Table(name = "emotion_reviews")
public class EmotionReviewEntity {
  @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  @Column(name = "content_id", nullable = false)
  private Long contentId;

  @Column(nullable = false, length = 100)
  private String author;

  @Column(name = "review_date", nullable = false)
  private LocalDateTime reviewDate;

  @Column(name = "before_emotion", nullable = false, length = 32)
  private String beforeEmotion;

  @Column(name = "after_emotion", nullable = false, length = 32)
  private String afterEmotion;

  @Column(name = "delta_valence", nullable = false)
  private Double deltaValence;

  @Column(name = "delta_arousal", nullable = false)
  private Double deltaArousal;

  @Column(name = "delta_dominance", nullable = false)
  private Double deltaDominance;

  @Lob
  private String content;

  @Column(name = "helpful_count", nullable = false)
  private Integer helpfulCount = 0;

  @Lob
  @Column(name = "images_json")
  private String imagesJson; // ["...","..."] (주석 ②)

  @Column(name = "created_at", nullable = false)
  private LocalDateTime createdAt = LocalDateTime.now();

  @Column(name = "updated_at", nullable = false)
  private LocalDateTime updatedAt = LocalDateTime.now();

  // getters/setters ...
}
