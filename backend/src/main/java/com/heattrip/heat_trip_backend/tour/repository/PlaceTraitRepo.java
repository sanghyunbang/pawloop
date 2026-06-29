// (선택) tour가 꼭 Repository가 필요하면, 엔티티는 curation의 것을 사용
package com.heattrip.heat_trip_backend.tour.repository;

import com.heattrip.heat_trip_backend.curation.entity.PlaceTrait;
import org.springframework.data.jpa.repository.JpaRepository;

public interface PlaceTraitRepo extends JpaRepository<PlaceTrait, String> {}
