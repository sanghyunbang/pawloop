package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * 방 멤버십 조회·입장 — 이슈 #74·#75.
 *
 * <p>메서드가 {@code Long roomId} 를 받지 {@code User} 를 받지 않는다. chat 은 사용자를
 * 값으로만 안다({@code ChatRoomMember} javadoc 참조).
 */
public interface ChatRoomMemberRepository extends JpaRepository<ChatRoomMember, Long> {

    Optional<ChatRoomMember> findByRoomIdAndUserId(Long roomId, Long userId);

    /** 방의 살아 있는 멤버. 강퇴된 행({@code removed_at} 이 찍힌 행)은 뺀다. */
    List<ChatRoomMember> findByRoomIdAndRemovedAtIsNull(Long roomId);

    /** 정원 검사의 좌변. 강퇴된 행은 정원을 차지하지 않는다. */
    long countByRoomIdAndRemovedAtIsNull(Long roomId);

    /**
     * 이 사람이 살아 있는 멤버로 있는, 같은 출처 종류의 방들 — 참여 순서대로.
     *
     * <p>{@code GET /api/groups/me} 가 이 조회로 답한다. 멤버십 표가 {@code chat_room_member}
     * 하나이기 때문에({@code group_member} 를 만들지 않는다 — ADR-0011 결정 1) "내가 속한
     * 가족" 을 아는 곳도 여기 하나다.
     *
     * <p>조인은 {@code chat_room} 까지다. 밖으로 나가지 않는다 —
     * {@code ChatBoundaryArchitectureTest} 의 §C 가 쿼리 문자열을 훑어 그것을 잠근다.
     */
    @Query("""
            select m from ChatRoomMember m
              join fetch m.room r
             where m.userId = :userId
               and m.removedAt is null
               and r.originKind = :originKind
             order by m.joinedAt asc, m.id asc
            """)
    List<ChatRoomMember> findLiveMembershipsByOriginKind(
            @Param("userId") Long userId, @Param("originKind") String originKind);

    /**
     * 방에 자리가 남아 있을 때만 멤버 한 줄을 넣는다. <b>영향 행 수가 곧 정원 판정이다.</b>
     *
     * <p>왜 자바에서 세고 나서 넣지 않는가: 그러면 세는 문장과 넣는 문장 사이에 다른 요청이
     * 들어와 마지막 자리를 함께 가져간다(📌 #86 원칙 5 — 확인-후-쓰기는 DB 로 받친다).
     * 조건을 같은 문장 안에 두면 계산 시점과 쓰기 시점이 갈라지지 않는다.
     *
     * <p><b>어디까지 보증하는가 — 과장하지 않고 적는다.</b> 참여 경로는 언제나
     * {@code ChatRoomInviteRepository.consumeOneUse} 를 먼저 통과하고, 그 조건부 UPDATE 가
     * 커밋까지 초대 행의 배타 잠금을 쥔다. 그래서 <b>같은 코드로 들어오는 동시 참여는 전부
     * 줄을 서고</b> 정원이 정확하다. 남는 창은 <b>같은 방에 살아 있는 코드가 여럿일 때</b>
     * 서로 다른 코드로 동시에 들어오는 경우이고, 그때는 동시 코드 수만큼 정원을 넘을 수 있다.
     * 지금 방마다 코드는 발급-회수로 관리되는 소수이고, 이 창을 없애려면 {@code chat_room}
     * 행을 잠그거나 멤버 수를 컬럼으로 들고 CHECK 를 걸어야 한다 — 둘 다 #78 이 시퀀스
     * 발급으로 잠금을 처음 들여올 때 함께 판단하는 것이 맞다.
     *
     * <p>네이티브 SQL 인 이유: JPQL 에는 {@code INSERT ... SELECT} 가 없다.
     * 조인 대상은 {@code chat_room}·{@code chat_room_member} 둘뿐이라 경계 안이다.
     *
     * @return 1 이면 들어왔고, 0 이면 정원이 찼거나 방이 사라졌다
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            insert into chat_room_member
                   (room_id, user_id, role, joined_at, last_read_seq, rejoin_blocked)
            select r.id, :userId, 'MEMBER', :now, 0, b'0'
              from chat_room r
             where r.id = :roomId
               and (select count(*) from chat_room_member m
                     where m.room_id = r.id and m.removed_at is null) < :capacity
            """, nativeQuery = true)
    int insertMemberIfRoomHasSpace(@Param("roomId") Long roomId,
                                   @Param("userId") Long userId,
                                   @Param("now") LocalDateTime now,
                                   @Param("capacity") int capacity);

    /**
     * 나갔던(또는 강퇴됐던) 사람의 <b>기존 행을 되살린다.</b> 새 행을 만들지 않는다.
     *
     * <p>{@code UNIQUE (room_id, user_id)} 가 새 행을 애초에 막고, 그게 아니어도 지우고 다시
     * 넣으면 {@code last_read_seq} 가 사라져 미읽음이 처음부터 다시 쌓인다
     * ({@code ChatRoomMember} javadoc — "행을 지우지 않는다").
     *
     * <p>{@code where ... and removed_at is not null} 이 조건부 UPDATE 다. 되살아난 뒤에
     * 다시 부르면 0 을 받는다 — 즉 두 번 되살아나 자리를 둘 쓰는 일이 없다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update ChatRoomMember m
               set m.removedAt = null, m.removedBy = null
             where m.id = :id and m.removedAt is not null
            """)
    int reviveIfRemoved(@Param("id") Long id);
}
