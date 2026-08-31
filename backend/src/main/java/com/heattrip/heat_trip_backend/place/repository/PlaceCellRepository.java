package com.heattrip.heat_trip_backend.place.repository;

import com.heattrip.heat_trip_backend.place.entity.PlaceCell;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;

/** 격자 셀 스냅샷 — 이슈 #40. */
public interface PlaceCellRepository extends JpaRepository<PlaceCell, PlaceCell.Key> {

    /**
     * 셀 실패를 기록한다. <b>스냅샷은 건드리지 않는다</b> — 있으면 계속 서빙해야 한다.
     *
     * <p>{@code fail_streak} 이 오르면 백오프가 길어진다. 실패한 호출도 예산을 태우므로
     * 백오프가 없으면 KTO 가 아픈 동안 예산이 순식간에 사라지고, 회복된 뒤에 쓸 것이 없다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update PlaceCell c
               set c.failedAt = :now, c.failStreak = c.failStreak + 1
             where c.latIdx = :latIdx and c.lngIdx = :lngIdx
            """)
    int recordFailure(@Param("latIdx") Integer latIdx,
                      @Param("lngIdx") Integer lngIdx,
                      @Param("now") LocalDateTime now);
}
