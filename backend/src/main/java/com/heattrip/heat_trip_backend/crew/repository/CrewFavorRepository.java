package com.heattrip.heat_trip_backend.crew.repository;

import com.heattrip.heat_trip_backend.crew.entity.CrewFavor;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;

/**
 * 품앗이 조회 — 이슈 #417.
 *
 * <h2>질문은 하나다 — "이 크루의 부탁"</h2>
 * <p>크루 홈이 목록을 그린다. 그 밖의 자리(내가 맡은 것 모아 보기 같은)는 <b>일정표가
 * 답한다</b> — 맡으면 크루 일정 한 줄이 생기고 그것이 내 달력에 뜬다. 여기에 같은 질문을
 * 또 만들면 두 목록이 서로 다른 말을 하는 날이 온다.
 */
public interface CrewFavorRepository extends JpaRepository<CrewFavor, Long> {

    /**
     * 그 크루의 부탁 — <b>지난 것은 빼고</b> 가까운 날짜부터.
     *
     * <p>지난 부탁을 남겨 두면 목록의 위쪽이 아무도 못 맡는 카드로 막힌다. 지우지는 않는다 —
     * 맡은 사람에게는 지난 약속도 기록이다. 안 보이게만 한다.
     *
     * <p>{@code join fetch} 셋은 <b>N+1 을 막는 것</b>이다. 카드마다 부탁한 사람·맡은 사람·
     * 아이를 따로 읽으면 부탁 20건에 쿼리가 60개다.
     */
    @Query("""
            select f from CrewFavor f
              left join fetch f.askedBy
              left join fetch f.takenBy
              left join fetch f.dog
             where f.crew.id = :crewId
               and f.onDate >= :from
             order by f.onDate asc, f.id asc
            """)
    List<CrewFavor> findUpcoming(@Param("crewId") long crewId,
                                 @Param("from") LocalDate from,
                                 Limit limit);

    /** 크루를 지울 때 함께 지운다. DB 의 {@code ON DELETE CASCADE} 가 받치지만, 맡은 것의 */
    /** 일정 줄까지 거두려면 행을 <b>읽어야</b> 한다 — 그 id 들이 거기 있다. */
    @Query("select f from CrewFavor f where f.crew.id = :crewId")
    List<CrewFavor> findAllOfCrew(@Param("crewId") long crewId);
}
