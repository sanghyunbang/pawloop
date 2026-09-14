package com.heattrip.heat_trip_backend.walk.repository;

import com.heattrip.heat_trip_backend.walk.entity.WeeklyInsight;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.Optional;

public interface WeeklyInsightRepository extends JpaRepository<WeeklyInsight, Long> {

    Optional<WeeklyInsight> findByUser_IdAndDogKeyAndWeekStart(long userId, long dogKey, LocalDate weekStart);
}
