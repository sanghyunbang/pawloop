package com.heattrip.heat_trip_backend.place.repository;

import com.heattrip.heat_trip_backend.place.entity.PlaceCatalog;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Optional;

/**
 * 출처별 장소 한 벌 — 이슈 #273 · #291. {@link PlaceCellRepository} 와 같은 모양이다.
 *
 * <p>행은 출처마다 하나이고 번호가 고정이다({@code CatalogSource.id()}). 그래서 조회가 전부
 * PK 다 — {@code source} 로 찾는 메서드를 두지 않는다.
 */
public interface PlaceCatalogRepository extends JpaRepository<PlaceCatalog, Integer> {

    /**
     * 실패를 기록한다. <b>{@code payload} 는 건드리지 않는다</b> — 있으면 계속 서빙해야 한다.
     *
     * <p>{@code fail_streak} 이 오르면 백오프가 길어진다. 실패한 호출도 예산을 태우므로
     * 백오프가 없으면 KTO 가 아픈 동안 예산이 순식간에 사라지고, 회복된 뒤에 쓸 것이 없다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update PlaceCatalog c
               set c.failedAt = :now, c.failStreak = c.failStreak + 1
             where c.id = :id
            """)
    int recordFailure(@Param("id") Integer id, @Param("now") LocalDateTime now);

    /**
     * ETag 만. {@code payload} 가 MB 단위라, "바뀌었는가" 만 물을 때 행을 통째로 읽으면 안 된다 —
     * {@code LayerPlaceIndex} 가 요청마다 이것으로 캐시가 낡았는지 본다(#291).
     */
    @Query("select c.etag from PlaceCatalog c where c.id = :id")
    Optional<String> etagOf(@Param("id") Integer id);
}
