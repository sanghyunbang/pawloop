// repository/EmotionFeedbackRepository.java
package com.heattrip.heat_trip_backend.explore.repository;

import com.heattrip.heat_trip_backend.explore.entity.EmotionFeedbackEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface EmotionFeedbackRepository extends JpaRepository<EmotionFeedbackEntity, Long> {
}
