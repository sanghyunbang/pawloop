package com.heattrip.heat_trip_backend.schedules.repository;

import com.heattrip.heat_trip_backend.schedules.entity.Journey;
import com.heattrip.heat_trip_backend.user.entity.User;
import java.util.List;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.stereotype.Repository;
import org.springframework.context.annotation.Primary;

@Repository
@Primary // ⬅ 기존 JourneyRepository와 공존한다면 v2를 우선 주입하도록 설정(선택)
public interface JourneyRepository_v2 extends JpaRepository<Journey, Long> {

    /** 유저의 전체 여정 */
    List<Journey> findByUser(User user);

    /** 필요 시 N+1 방지를 위해 스케줄을 즉시 로딩하는 변형(옵션) */
    @EntityGraph(attributePaths = {"schedule"})
    List<Journey> findWithScheduleByUser(User user);
    int countBySchedule_ScheduleId(Integer scheduleId);

    /**
     * B2-2 UGC 감정 집계용: place_id 가 채워져 있고 moodLabel 이 비어있지 않은 다이어리만 페이징 조회.
     * (장소와 연결되지 않았거나 기분이 없는 항목은 집계 대상이 아니다.)
     */
    @Query("SELECT j FROM Journey j WHERE j.placeId IS NOT NULL "
            + "AND j.moodLabel IS NOT NULL AND j.moodLabel <> ''")
    Page<Journey> findForUgcAggregation(Pageable pageable);
}
