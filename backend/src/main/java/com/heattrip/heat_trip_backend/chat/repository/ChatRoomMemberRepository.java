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
     * <p><b>어디까지 보증하는가 — 실측대로 적는다.</b> 이 문단은 예전에 "남는 창은 서로 다른
     * 코드로 동시에 들어올 때이고 그때는 정원을 넘을 수 있다" 고 적혀 있었다. <b>스레드를
     * 띄워 보니 관측된 증상은 정원 초과가 아니었다.</b> 정원 50 인 방에 50명을 동시에 밀어
     * 넣어도 최종 멤버는 정확히 50이었고, 대신 나온 것은
     * {@code Deadlock found when trying to get lock} → 500 이었다(4명 동시에 3명이 졌다).
     * 이 문장이 같은 인덱스 범위를 <b>읽으면서(정원 세는 서브쿼리) 그 범위에 INSERT</b> 하기
     * 때문이고, 두 트랜잭션이 서로의 잠금을 기다리면 InnoDB 가 한쪽을 죽인다.
     *
     * <p>그래서 참여 경로는 {@code ChatRoomRepository#lockForMemberChange} 로 <b>방을 잠그고
     * 시작한다.</b> 같은 방에 대한 참여는 코드가 몇 개든 한 줄로 서므로 이 문장이 자기 자신과
     * 경합하지 않는다. 락 순서는 그 메서드 javadoc 에 못 박혀 있다 —
     * {@code chat_room → chat_room_invite → chat_room_member}. <b>그 순서를 어기는 경로를
     * 새로 만들면 데드락이 돌아온다.</b>
     *
     * <p>{@code consumeOneUse} 의 초대 행 배타 잠금은 그대로 남아 있지만, 이제 그것이 정원의
     * 근거는 아니다 — 그 잠금은 <b>같은 코드</b>만 줄 세우고 방을 줄 세우지 못한다.
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
     *
     * <p><b>여기서 0 은 "자리가 없다" 가 아니라 "이미 되살아났다" 다.</b> 호출부가 그 0 을
     * {@code ROOM_MEMBER_LIMIT} 로 옮겨 정원 50 인 방에 2명일 때 "정원이 찼습니다" 를 낸
     * 적이 있다({@code ChatRoomService#reviveWithinCapacity} javadoc). 정원은 정원 검사가
     * 답하고, 이 0 은 멱등 200 이다.
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("""
            update ChatRoomMember m
               set m.removedAt = null, m.removedBy = null
             where m.id = :id and m.removedAt is not null
            """)
    int reviveIfRemoved(@Param("id") Long id);
}
