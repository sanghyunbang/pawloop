package com.heattrip.heat_trip_backend.tour.repository;

import com.heattrip.heat_trip_backend.tour.domain.PlaceHashtag;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PlaceHashtagRepo extends JpaRepository<PlaceHashtag, Long> {
    /** 이번 배치 청크에서 필요한 CAT3 묶음만 한번에 조회 */
    List<PlaceHashtag> findByPlaceIdIn(Iterable<String> placeIds);
}
