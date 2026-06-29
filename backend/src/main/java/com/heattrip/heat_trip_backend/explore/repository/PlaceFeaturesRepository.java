// repository/PlaceFeaturesRepository.java
package com.heattrip.heat_trip_backend.explore.repository;

import com.heattrip.heat_trip_backend.explore.entity.PlaceFeaturesEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PlaceFeaturesRepository extends JpaRepository<PlaceFeaturesEntity, Long> {
  // link_id(=contentId)로 단건 조회 (주석 ①)
}
