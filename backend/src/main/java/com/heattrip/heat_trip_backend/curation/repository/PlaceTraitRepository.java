// src/main/java/com/heattrip/heat_trip_backend/curation/repository/PlaceTraitRepository.java
package com.heattrip.heat_trip_backend.curation.repository;

import com.heattrip.heat_trip_backend.curation.entity.PlaceTrait;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;

public interface PlaceTraitRepository extends JpaRepository<PlaceTrait, String> {

    // 1) 한글 라벨(=name)로 CAT3(=placeId) 찾기
    @Query("""
        select distinct t.placeId
          from PlaceTrait t
         where t.name in :labels
        """)
    List<String> findCat3ByLabelIn(@Param("labels") Collection<String> labels);

    // 2) 공백 제거 정규화 비교 (Hibernate 6: function 사용)
    @Query("""
        select distinct t.placeId
          from PlaceTrait t
         where function('replace', t.name, ' ', '') in :labelsNormalized
        """)
    List<String> findCat3ByNormalizedLabelIn(@Param("labelsNormalized") Collection<String> labelsNormalized);

    // 3) 사전 빌드용: (라벨, CAT3) 페어 전부
    @Query("""
        select distinct t.name, t.placeId
          from PlaceTrait t
         where t.name is not null and t.placeId is not null
        """)
    List<Object[]> findAllDistinctPairs();
}
