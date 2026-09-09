package com.heattrip.heat_trip_backend.schedule.repository;

import com.heattrip.heat_trip_backend.schedule.entity.Schedule;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;

/**
 * 일정 조회 — 이슈 #418.
 *
 * <h2>조회는 <b>주인 목록</b>으로 받는다</h2>
 * <p>달력의 기본이 "합쳐 보기" 다 — 내 아이들 것과 우리 가족 것이 한 목록으로 나온다.
 * 주인 하나씩 물으면 화면이 N 번 부르고, 그 N 개를 날짜순으로 다시 섞어야 한다.
 *
 * <p>그래서 {@code (kind, ref)} 쌍의 목록을 한 번에 받는다. 쌍을 튜플로 넘길 수 없어
 * <b>두 목록을 짝지어</b> 보낸다 — {@code owner_kind = :k AND owner_ref IN (...)} 를
 * 종류별로 나눠 부르는 편이 인덱스({@code owner_kind, owner_ref, on_date})를 그대로 탄다.
 *
 * <h2>정렬</h2>
 * <p>날짜 → 시각 → id. <b>시각이 없는 것이 뒤</b>다({@code atTime is null} 을 나중으로) —
 * 화면이 "시각 있는 것 먼저, 하루 종일은 묶어서" 로 그린다.
 */
public interface ScheduleRepository extends JpaRepository<Schedule, Long> {

    /**
     * 한 주인의 기간 조회.
     *
     * <p>{@code refs} 가 비면 호출하지 않는다 — JPA 의 빈 {@code IN ()} 은 DB 마다 다르게
     * 처리된다. 서비스가 먼저 거른다.
     *
     * <h2>반복 규칙은 기간 밖에서도 걸린다</h2>
     * <p>이슈 #421. 매주 화요일 규칙의 {@code on_date} 는 <b>시작한 날</b>이라 조회 기간보다
     * 훨씬 앞일 수 있다 — 작년에 시작한 심장사상충 약이 그렇다. {@code on_date between} 만
     * 보면 그 규칙이 한 줄도 안 나온다.
     *
     * <p>그래서 되풀이하는 행은 <b>시작일이 기간 끝보다 앞이고 종료일이 기간 시작보다
     * 뒤인</b> 것을 전부 가져온다. 실제로 그 기간에 오는 날이 있는지는 서버가 펼치며
     * 가른다({@code ScheduleExpansion}).
     */
    @Query("""
            select s from Schedule s
              left join fetch s.dog
              left join fetch s.assignee
             where s.ownerKind = :kind
               and s.ownerRef in :refs
               and (
                     (s.repeatKind = com.heattrip.heat_trip_backend.schedule.entity.ScheduleRepeat.NONE
                      and s.onDate between :from and :to)
                  or (s.repeatKind <> com.heattrip.heat_trip_backend.schedule.entity.ScheduleRepeat.NONE
                      and s.onDate <= :to
                      and (s.repeatUntil is null or s.repeatUntil >= :from))
                   )
             order by s.onDate asc, s.atTime asc nulls last, s.id asc
            """)
    List<Schedule> findRange(@Param("kind") ScheduleOwnerKind kind,
                             @Param("refs") List<Long> refs,
                             @Param("from") LocalDate from,
                             @Param("to") LocalDate to);
}
