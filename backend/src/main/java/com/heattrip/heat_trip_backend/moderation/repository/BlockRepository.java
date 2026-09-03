package com.heattrip.heat_trip_backend.moderation.repository;

import com.heattrip.heat_trip_backend.moderation.entity.Block;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

/**
 * 가리기 저장소 — 이슈 #82.
 *
 * <p>{@code chat_block} 은 {@code chat} 경계 <b>안</b>이고 두 컬럼 다 불투명한 값이다.
 * 여기서 {@code users} 를 조인하지 않는다({@code ChatBoundaryArchitectureTest} 가 잠근다).
 */
public interface BlockRepository extends JpaRepository<Block, Long> {

    /**
     * 내가 가린 사람들의 id.
     *
     * <p><b>엔티티가 아니라 id 만</b> 가져온다. 메시지 한 장을 그릴 때마다 부르는 조회라
     * 행을 영속성 컨텍스트에 올릴 이유가 없다.
     */
    @Query("select b.blockedUserId from Block b where b.blockerUserId = :blockerUserId")
    List<Long> findBlockedIdsOf(@Param("blockerUserId") Long blockerUserId);

    boolean existsByBlockerUserIdAndBlockedUserId(Long blockerUserId, Long blockedUserId);

    /**
     * 가리기를 푼다.
     *
     * <p>지운 행 수를 돌려주는 것이 <b>없던 것을 풀었는지</b>를 부르는 쪽이 알 수 있게 한다.
     * 계약은 그 경우도 204 지만, 그것을 결정하는 것은 여기가 아니다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("delete from Block b "
            + "where b.blockerUserId = :blockerUserId and b.blockedUserId = :blockedUserId")
    int deleteBlock(@Param("blockerUserId") Long blockerUserId,
                    @Param("blockedUserId") Long blockedUserId);
}
