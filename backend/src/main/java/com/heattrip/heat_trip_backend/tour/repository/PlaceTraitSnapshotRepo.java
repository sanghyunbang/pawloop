package com.heattrip.heat_trip_backend.tour.repository;

import com.heattrip.heat_trip_backend.tour.domain.PlaceTraitSnapshot;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PlaceTraitSnapshotRepo extends JpaRepository<PlaceTraitSnapshot, String> {}
