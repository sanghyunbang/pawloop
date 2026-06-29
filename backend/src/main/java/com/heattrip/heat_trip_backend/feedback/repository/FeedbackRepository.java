// src/main/java/com/heattrip/heat_trip_backend/feedback/repository/FeedbackRepository.java
package com.heattrip.heat_trip_backend.feedback.repository;

import com.heattrip.heat_trip_backend.feedback.entity.Feedback;
import org.springframework.data.jpa.repository.JpaRepository;
// @Repository 어노테이션은 생략 가능(Spring Data JPA가 자동으로 빈 등록)

public interface FeedbackRepository extends JpaRepository<Feedback, Long> {
}
