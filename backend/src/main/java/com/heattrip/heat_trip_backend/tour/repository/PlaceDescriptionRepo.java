package com.heattrip.heat_trip_backend.tour.repository;

import com.heattrip.heat_trip_backend.tour.domain.PlaceDescription;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PlaceDescriptionRepo extends JpaRepository<PlaceDescription, String> {
    List<PlaceDescription> findByPlaceIdIn(Iterable<String> placeIds);
}
