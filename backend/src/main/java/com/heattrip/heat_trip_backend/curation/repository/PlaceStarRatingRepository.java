package com.heattrip.heat_trip_backend.curation.repository;

import com.heattrip.heat_trip_backend.curation.entity.PlaceStarRating;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;

@Repository
public interface PlaceStarRatingRepository extends JpaRepository<PlaceStarRating, Long> {

    interface RatingAgg {
        Long getLinkId();
        Double getAvgRating();
        Long getNRows();
    }

    @Query(value = """
        SELECT link_id   AS linkId,
               AVG(rating) AS avgRating,
               COUNT(*)    AS nRows
          FROM place_star_ratings
         WHERE link_id IN (:ids)
         GROUP BY link_id
        """, nativeQuery = true)
    List<RatingAgg> avgByLinkIds(@Param("ids") Collection<Long> ids);
}
