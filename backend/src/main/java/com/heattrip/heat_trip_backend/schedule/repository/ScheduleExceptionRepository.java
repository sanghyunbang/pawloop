package com.heattrip.heat_trip_backend.schedule.repository;

import com.heattrip.heat_trip_backend.schedule.entity.ScheduleException;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;

/**
 * 반복 규칙의 하루짜리 예외 — 이슈 #421.
 *
 * <h2>규칙 목록으로 한 번에 읽는다</h2>
 * <p>펼치기는 규칙마다 "이 날짜가 예외인가" 를 묻는데, 그것을 규칙마다 한 번씩 물으면
 * 한 달 조회에 쿼리가 규칙 수만큼 늘어난다. 기간 안의 예외를 <b>한 번에</b> 받아
 * 메모리에서 가른다 — 한 달치 예외는 많아야 수십 줄이다.
 */
public interface ScheduleExceptionRepository
        extends JpaRepository<ScheduleException, ScheduleException.Key> {

    @Query("""
            select e from ScheduleException e
             where e.schedule.id in :scheduleIds
               and e.onDate between :from and :to
            """)
    List<ScheduleException> findRange(@Param("scheduleIds") List<Long> scheduleIds,
                                      @Param("from") LocalDate from,
                                      @Param("to") LocalDate to);

    /** 이 규칙의 그날 예외. 같은 날에 두 번 손대는 것을 막는 자리다. */
    @Query("""
            select e from ScheduleException e
             where e.schedule.id = :scheduleId and e.onDate = :onDate
            """)
    java.util.Optional<ScheduleException> findOne(@Param("scheduleId") long scheduleId,
                                                  @Param("onDate") LocalDate onDate);
}
