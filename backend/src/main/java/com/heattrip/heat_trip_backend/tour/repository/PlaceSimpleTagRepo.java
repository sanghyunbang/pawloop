package com.heattrip.heat_trip_backend.tour.repository;

import com.heattrip.heat_trip_backend.tour.domain.PlaceSimpleTag;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PlaceSimpleTagRepo extends JpaRepository<PlaceSimpleTag, Long> {
    List<PlaceSimpleTag> findByPlaceIdIn(Iterable<String> placeIds);
}
