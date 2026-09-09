package com.heattrip.heat_trip_backend.crew.repository;

import com.heattrip.heat_trip_backend.crew.entity.Crew;
import com.heattrip.heat_trip_backend.crew.entity.CrewVisibility;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;

/**
 * 크루 조회 — 이슈 #417.
 *
 * <h2>목록 질문은 둘뿐이다</h2>
 * <ol>
 *   <li><b>우리 동네 공개 크루</b> — 시군구 앞자리로 찾는다.</li>
 *   <li><b>내가 든 크루</b> — 그건 이 표가 아니라 {@code chat_room_member} 가 답한다.
 *       서비스가 방 목록을 받아 그 {@code origin_ref} 로 여기서 꺼낸다.</li>
 * </ol>
 */
public interface CrewRepository extends JpaRepository<Crew, Long> {

    /**
     * 우리 동네의 공개 크루. <b>앞 다섯 자리(시군구)로 찾는다.</b>
     *
     * <p>행정동 열 자리를 그대로 맞추면 같은 구의 옆 동네 모임이 안 보인다 — 동네 모임은
     * 구 단위로 움직인다({@code users.neighborhood_code} 로 커뮤니티가 같은 판단을 했다,
     * #342). 앞자리 {@code LIKE} 라 {@code idx_crew_public} 을 그대로 탄다.
     *
     * <p>{@code neighborhood_code} 가 {@code null} 인 크루는 안 나온다 — 동네를 안 고른
     * 크루라, 어느 동네 목록에도 속하지 않는다. (그런 크루는 공개로 만들 수 없다 —
     * {@code CrewService.validNeighborhood} 가 앞에서 막는다. 여기서 또 안 뜨는 것은
     * <b>공개로 만든 뒤에 동네만 지운</b> 경로가 생겨도 조용히 맞게 두려는 것이다.)
     *
     * <p><b>{@code Limit} 를 받는다.</b> 한 판을 안 자르면 동네 하나에 크루가 몇천 개가 된
     * 날 이 문장이 그걸 전부 실어 온다 — 그날은 목록 화면이 느린 것이 아니라 안 뜬다.
     */
    @Query("""
            select c from Crew c
             where c.visibility = :visibility
               and c.neighborhoodCode like concat(:sggPrefix, '%')
             order by c.createdAt desc, c.id desc
            """)
    List<Crew> findPublicIn(@Param("visibility") CrewVisibility visibility,
                            @Param("sggPrefix") String sggPrefix,
                            Limit limit);

    /**
     * 방 목록에서 꺼낸 id 들. 순서는 부르는 쪽이 다시 세운다.
     *
     * <p>{@code ids} 가 비어 있으면 빈 목록이다 — 빈 {@code IN} 을 벤더가 어떻게 번역하는지에
     * 기대지 않는다.
     */
    default List<Crew> findAllByIdIn(Collection<Long> ids) {
        return ids == null || ids.isEmpty() ? List.of() : findAllById(ids);
    }
}
