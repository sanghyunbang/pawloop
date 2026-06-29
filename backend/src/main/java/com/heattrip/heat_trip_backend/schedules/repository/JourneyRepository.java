package com.heattrip.heat_trip_backend.schedules.repository;

import com.heattrip.heat_trip_backend.schedules.entity.Journey;
import com.heattrip.heat_trip_backend.user.entity.*;


import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface JourneyRepository extends JpaRepository<Journey, Integer> {
    List<Journey> findByUser(User user);
}
