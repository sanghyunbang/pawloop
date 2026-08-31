package com.heattrip.heat_trip_backend.place.repository;

import com.heattrip.heat_trip_backend.place.entity.KtoCallBudgetRow;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;

/**
 * 호출 예산 표 — 이슈 #40.
 *
 * <p>세 문장 다 <b>네이티브</b>다. JPQL 로는 {@code INSERT} 를 쓸 수 없고, 예약은
 * "읽어서 비교하고 쓰기" 가 아니라 <b>한 문장</b>이어야 하기 때문이다.
 */
public interface KtoCallBudgetRepository extends JpaRepository<KtoCallBudgetRow, KtoCallBudgetRow.Key> {

    /**
     * 오늘 행을 만들어 둔다. 이미 있으면 아무것도 안 한다.
     *
     * <p>이게 없으면 <b>자정을 넘긴 첫 요청이 영원히 실패한다</b> — 아래 UPDATE 는 행이
     * 있어야 걸리는데, 그날 첫 호출은 행이 없어서 0행을 받고, 그 결과 "예산 없음" 으로
     * 판정되어 행이 영영 안 생긴다.
     *
     * <p>{@code INSERT IGNORE} 인 이유: 두 요청이 동시에 들어오면 뒤에 오는 쪽이 PK 중복으로
     * 터진다. 그 예외를 잡아 무시하는 것과 결과가 같지만, 예외를 만들지 않는 쪽이 낫다 —
     * 예외는 로그를 더럽히고 그 로그를 보는 사람이 진짜 문제로 오해한다.
     */
    @Modifying
    @Query(value = "insert ignore into kto_call_budget (`day`, pool, used) values (:day, :pool, 0)",
            nativeQuery = true)
    void ensureRow(@Param("day") LocalDate day, @Param("pool") String pool);

    /**
     * 호출 {@code units} 개를 예약한다. <b>이 한 문장이 상한을 지킨다.</b>
     *
     * <h2>조건이 {@code SET} 이 아니라 {@code WHERE} 에 있는 것이 요점이다</h2>
     * <p>이렇게 쓰면 안 된다:
     * <pre>
     *   update kto_call_budget set used = if(used + :units &lt;= :cap, used + :units, used) ...
     * </pre>
     * <p>MySQL Connector/J 는 기본이 {@code CLIENT_FOUND_ROWS} 라 <b>값이 안 바뀐 행도
     * "1행 영향" 으로</b> 돌려준다({@code useAffectedRows} 를 켜지 않는 한). 그래서 예산이
     * 소진된 상태에서도 이 판정이 통과하고, 그 순간부터 상한이 없다.
     *
     * <p>조건을 {@code WHERE} 에 두면 소진 상태에서는 <b>매칭되는 행 자체가 없다.</b>
     * 설정과 무관하게 0 이 온다.
     *
     * @return 예약에 성공하면 1, 예산이 없으면 0
     */
    @Modifying
    @Query(value = """
            update kto_call_budget
               set used = used + :units
             where `day` = :day and pool = :pool and used + :units <= :cap
            """, nativeQuery = true)
    int reserve(@Param("day") LocalDate day,
                @Param("pool") String pool,
                @Param("units") int units,
                @Param("cap") int cap);

    /**
     * 이 풀을 오늘치 전부 소진한 것으로 닫는다.
     *
     * <p>KTO 가 {@code resultCode=22}(한도 초과) 나 {@code 30}(키 미등록)을 주면 부른다 —
     * <b>상대의 말을 우리 카운터보다 믿는다.</b> 우리 계산이 맞더라도 상대가 아니라고 하면
     * 아닌 것이고, 그 상태로 계속 두드리면 차단당한다.
     */
    @Modifying
    @Query(value = "update kto_call_budget set used = :cap where `day` = :day and pool = :pool",
            nativeQuery = true)
    int close(@Param("day") LocalDate day, @Param("pool") String pool, @Param("cap") int cap);
}
