package com.heattrip.heat_trip_backend.curation.repository;

import com.heattrip.heat_trip_backend.curation.entity.Cat3CategoryMapping;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;
import java.util.Set;

public interface Cat3CategoryMappingRepository extends JpaRepository<Cat3CategoryMapping, Long> {

    List<Cat3CategoryMapping> findByCat3CodeIn(Set<String> codes);

    /** emotion 카테고리 → cat3 목록 조회 (필요 시 사용) */
    @Query("select m from Cat3CategoryMapping m where m.categoryId in ?1")
    List<Cat3CategoryMapping> findByCategoryIdIn(Set<Integer> categoryIds);
}
