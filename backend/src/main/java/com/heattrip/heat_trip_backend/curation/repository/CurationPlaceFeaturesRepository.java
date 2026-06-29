package com.heattrip.heat_trip_backend.curation.repository;

import com.heattrip.heat_trip_backend.curation.entity.PlaceFeatures;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;

@Repository("curationPlaceFeaturesRepository")
public interface CurationPlaceFeaturesRepository extends JpaRepository<PlaceFeatures, Long> {

    List<PlaceFeatures> findByPlaceIdIn(Collection<Long> ids);
}
/** place_features 테이블 매핑
 * - link_id == places.contentid
 * - feature(−1..1) → 서비스에서 0..1로 변환해 사용
 * - conf_*: 0..1 (신뢰도)
 */