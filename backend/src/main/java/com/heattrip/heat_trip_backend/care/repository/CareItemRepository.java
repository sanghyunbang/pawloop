package com.heattrip.heat_trip_backend.care.repository;

import com.heattrip.heat_trip_backend.care.entity.CareItem;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

/**
 * 그 집이 챙기는 일의 목록 — 이슈 #560.
 *
 * <p>축은 하나다. <b>"그 집의 항목을 순서대로"</b> — 카드도 고치기 화면도 같은 목록을 본다.
 * 다른 축이 생기면 그때마다 인가를 어디서 하는지 다시 정해야 한다
 * ({@code CareLogRepository} 의 판단과 같다).
 */
public interface CareItemRepository extends JpaRepository<CareItem, Long> {

    /**
     * 그 집의 항목 전부 — 접힌 것까지, 순서대로.
     *
     * <h2>⚠️ {@code i.group.id = :groupId} 를 지우면 안 된다 — 인가와 <b>다른</b> 방어다</h2>
     *
     * <p>인가({@code FamilyMembership.requireMember})는 <b>요청을 통째로</b> 막고, 이 줄은
     * 통과한 요청이 <b>어느 행을 보는지</b> 를 정한다. 한 사람이 여러 방에 속하는 것은
     * 정상이라(초대코드로 들어오면 그렇게 된다) 인가만으로는 옆집 목록이 샌다 —
     * {@code CareLogRepository.findByGroupAndDay} 의 javadoc 이 그 실측을 적어 뒀다.
     *
     * <p><b>접힌 것도 준다.</b> 고치기 화면이 "다시 켜기" 를 그리려면 접힌 것을 봐야 하고,
     * 카드는 {@code archivedAt == null} 로 거른다. 두 화면이 쿼리를 나눠 갖지 않는 이유는,
     * 나누면 "접힘" 의 정의가 두 곳에 생기기 때문이다.
     *
     * <p>{@code join fetch} 로 아이를 함께 끈다. 없으면 항목 수만큼 {@code dog} 왕복이 붙는다
     * ({@code DogRepository.findMine} 이 같은 이유로 같은 것을 한다).
     */
    @Query("""
            select i from CareItem i
              left join fetch i.dog
             where i.group.id = :groupId
             order by i.sortOrder asc, i.id asc
            """)
    List<CareItem> findOfGroup(@Param("groupId") long groupId);
}
