package com.heattrip.heat_trip_backend.curation.repository;

import com.heattrip.heat_trip_backend.curation.entity.Place;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Collection;
import java.util.List;

@Repository("curationPlaceRepository")
public interface CurationPlaceRepository extends JpaRepository<Place, Long> {

    List<Place> findByCat3In(Collection<String> cat3Codes);

    /** seed_emotion 이 아직 채워지지 않은 장소만 페이징 조회 (배치 비-overwrite 모드). */
    Page<Place> findBySeedEmotionIsNull(Pageable pageable);

    /**
     * F2-1: (lat,lng) 반경에 대한 바운딩 박스 조회.
     * mapy=위도(lat), mapx=경도(lng) 가정. 전체 테이블 스캔을 피하기 위한 1차 필터이며,
     * 정확한 반경 컷은 호출부에서 Haversine 으로 다시 거른다.
     */
    List<Place> findByMapyBetweenAndMapxBetween(double mapyMin, double mapyMax,
                                                double mapxMin, double mapxMax);

    /**
     * F2-2(탐색/search): title LIKE %q% 키워드 검색. 파라미터 바인딩으로 SQL 인젝션을 회피한다.
     * limit 는 Pageable 로 전달해 전체 스캔 결과가 무한정 커지는 것을 막는다.
     */
    List<Place> findByTitleContaining(String q, Pageable pageable);

    /**
     * F2-2(탐색/search): 감정 데이터(seed 또는 ugc)가 있는 장소만 바운딩 박스로 조회.
     * mood 만 주어지고 q 가 없을 때, 감정 데이터가 없는 장소까지 끌어오는 것을 피하기 위한 후보 축소용.
     */
    @Query("select p from CurationPlace p "
            + "where p.mapy between :mapyMin and :mapyMax "
            + "and p.mapx between :mapxMin and :mapxMax "
            + "and (p.seedEmotion is not null or p.ugcEmotion is not null)")
    List<Place> findEmotionalInBox(@Param("mapyMin") double mapyMin,
                                   @Param("mapyMax") double mapyMax,
                                   @Param("mapxMin") double mapxMin,
                                   @Param("mapxMax") double mapxMax);

    /**
     * F2-2(탐색/search): 위치 미제공 시 감정 데이터가 있는 장소를 하드 캡(Pageable)으로 조회.
     * 바운딩 박스가 없으므로 전체 스캔을 피하기 위해 반드시 limit 를 건다.
     */
    @Query("select p from CurationPlace p "
            + "where p.seedEmotion is not null or p.ugcEmotion is not null")
    List<Place> findEmotionalCapped(Pageable pageable);
}
