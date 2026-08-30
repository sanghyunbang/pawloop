package com.heattrip.heat_trip_backend.care.repository;

import com.heattrip.heat_trip_backend.care.entity.CareLog;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 케어 기록 조회 — 이슈 #76.
 *
 * <p>메서드가 하나뿐인 것이 의도다. "그룹의 하루" 말고 다른 축으로 읽는 화면이 아직 없고,
 * 축을 늘리면 그때마다 인가를 어디서 하는지 다시 정해야 한다.
 */
public interface CareLogRepository extends JpaRepository<CareLog, Long> {

    /**
     * 한 그룹의 하루치 기록 — 이른 것부터.
     *
     * <h2>⚠️ {@code c.group.id = :groupId} 를 지우면 안 된다 — 인가와 <b>다른</b> 방어다</h2>
     * <p>이 이슈에는 남의 기록을 막는 장치가 <b>둘</b> 있고 둘은 서로를 대신하지 않는다.
     * <ul>
     *   <li><b>인가</b>({@code CareService.requireMemberGroup}) — 요청자가 그 그룹의 방
     *       멤버가 아니면 403. <b>요청을 통째로</b> 막는다.</li>
     *   <li><b>필터</b>(이 줄) — 통과한 요청이 <b>어느 행을 보는지</b> 를 정한다.</li>
     * </ul>
     * <p>인가만 있고 필터가 없으면 <b>그 그룹의 멤버가 다른 그룹의 기록까지 본다.</b>
     * 한 사람이 여러 방에 속하는 것은 정상이므로(초대코드로 들어오면 그렇게 된다) 이건
     * 가정이 아니라 실제로 일어나는 상태다.
     *
     * <p><b>둘을 각각 되돌려 실측했다</b>(완료 조건 5·6).
     * <ul>
     *   <li>이 줄만 지우면 {@code CareSharingIntegrationTest} 11건 중 <b>4건</b>이 빨간불이고,
     *       그 중심이 {@code aMemberOfTwoGroups_seesOnlyTheGroupTheyAskedFor} 다 — 두 가족에
     *       모두 속한 사람에게 옆집 기록이 함께 나왔다. 나머지 셋도 전부 <b>행이 새는 것</b>을
     *       보는 단언이고, <b>403 을 보는 단언은 하나도 죽지 않았다.</b></li>
     *   <li>반대로 {@code CareService} 의 멤버십 검사만 지우면 <b>1건</b>만 빨간불이다 —
     *       {@code anOutsider_isForbiddenAndSeesNoRowOfSomeoneElsesFamily}. 이 필터는 그대로
     *       도는데도 남의 그룹 기록이 200 으로 통째로 나갔다.</li>
     * </ul>
     * <p>죽는 테스트가 서로 다르다는 것이 곧 "둘은 다른 방어" 라는 증거다.
     *
     * <p>{@code left join fetch c.doneBy} 는 응답의 이름 때문이다. 없으면 기록 수만큼
     * {@code users} 조회가 더 나간다 — {@code FamilyGroupService.nicknamesOf} 가 같은 이유로
     * 한 번에 모은다.
     *
     * <p><b>{@code left} 여야 한다.</b> {@code done_by} 는 {@code ON DELETE SET NULL} 이라
     * 수행자가 탈퇴한 행은 {@code null} 을 든다({@code CareLog.doneBy} javadoc). inner join 이면
     * 그 행이 조회에서 <b>조용히 빠지고</b>, 화면에서는 CASCADE 로 지우던 옛 동작과 구별되지
     * 않는다 — 즉 FK 만 고치고 여기를 안 고치면 아무것도 안 고친 것이다.
     *
     * <p>경계는 <b>[from, to)</b> 다. {@code between} 은 양끝을 포함해서 하루의 마지막
     * 마이크로초와 다음 날 00:00:00.000000 이 둘 다 걸린다.
     */
    @Query("""
            select c from CareLog c
              left join fetch c.doneBy
             where c.group.id = :groupId
               and c.occurredAt >= :from
               and c.occurredAt <  :to
             order by c.occurredAt asc, c.id asc
            """)
    List<CareLog> findDayOfGroup(@Param("groupId") long groupId,
                                 @Param("from") LocalDateTime from,
                                 @Param("to") LocalDateTime to);
}
