// repository/EmotionReviewRepository.java
package com.heattrip.heat_trip_backend.explore.repository;

import com.heattrip.heat_trip_backend.explore.entity.EmotionReviewEntity;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EmotionReviewRepository extends JpaRepository<EmotionReviewEntity, Long> {
  List<EmotionReviewEntity> findByContentIdOrderByReviewDateDesc(Long contentId);
}
