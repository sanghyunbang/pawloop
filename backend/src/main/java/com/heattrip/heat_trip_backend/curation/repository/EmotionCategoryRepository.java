package com.heattrip.heat_trip_backend.curation.repository;

import com.heattrip.heat_trip_backend.curation.entity.EmotionCategory;
import org.springframework.data.jpa.repository.JpaRepository;

public interface EmotionCategoryRepository extends JpaRepository<EmotionCategory, Integer> { }
