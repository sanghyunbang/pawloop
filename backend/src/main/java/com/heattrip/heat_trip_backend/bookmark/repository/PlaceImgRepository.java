package com.heattrip.heat_trip_backend.bookmark.repository;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PlaceImgRepository extends JpaRepository<Place, Long> {
}
