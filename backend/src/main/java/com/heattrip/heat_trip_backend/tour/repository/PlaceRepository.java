package com.heattrip.heat_trip_backend.tour.repository;

import java.util.Collection;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import com.heattrip.heat_trip_backend.tour.domain.Place;

public interface PlaceRepository extends JpaRepository<Place, Long>{

    @Modifying
    @Query(value = """
        UPDATE places p
        LEFT JOIN place_trait_snapshots s ON s.cat3 = p.cat3
        SET p.search_text = TRIM(CONCAT_WS(' ',
            NULLIF(TRIM(p.title), ''),
            NULLIF(TRIM(p.cat1), ''),
            NULLIF(TRIM(p.cat2), ''),
            NULLIF(TRIM(p.cat3), ''),
            NULLIF(TRIM(s.cat3name), ''),
            NULLIF(TRIM(s.short_desc1), ''),
            NULLIF(TRIM(s.short_desc2), '')
        ))
        """, nativeQuery = true)
    int refreshAllSearchTexts();

    @Modifying
    @Query(value = """
        UPDATE places p
        LEFT JOIN place_trait_snapshots s ON s.cat3 = p.cat3
        SET p.search_text = TRIM(CONCAT_WS(' ',
            NULLIF(TRIM(p.title), ''),
            NULLIF(TRIM(p.cat1), ''),
            NULLIF(TRIM(p.cat2), ''),
            NULLIF(TRIM(p.cat3), ''),
            NULLIF(TRIM(s.cat3name), ''),
            NULLIF(TRIM(s.short_desc1), ''),
            NULLIF(TRIM(s.short_desc2), '')
        ))
        WHERE p.cat3 IN (:cat3Codes)
        """, nativeQuery = true)
    int refreshSearchTextsByCat3Codes(@Param("cat3Codes") Collection<String> cat3Codes);
}
