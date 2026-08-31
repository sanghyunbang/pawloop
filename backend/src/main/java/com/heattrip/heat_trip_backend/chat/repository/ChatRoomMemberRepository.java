package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
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
     * 이 사람이 살아 있는 멤버로 있는 <b>모든</b> 방 — 참여 순서대로(이슈 #79).
     *
     * <p>{@link #findLiveMembershipsByOriginKind} 와 갈리는 지점은 {@code originKind} 필터
     * 하나다. {@code GET /api/groups/me} 는 "가족 방" 을 묻지만
     * {@code GET /api/chat/rooms} 는 <b>방 종류를 가리지 않는다</b> — 채팅은 가족 그룹
     * 종속이 아니라 범용 다중 방이고(ADR-0011), 앱의 방 목록 화면은 이미 종류가 다른 방
     * 둘을 나란히 그린다.
     *
     * <p>{@code join fetch} 가 방을 함께 읽는다. 없으면 방마다 지연 로딩이 한 번씩 나가
     * 방 20개에 쿼리가 21개다.
     */
    @Query("""
            select m from ChatRoomMember m
              join fetch m.room r
             where m.userId = :userId
               and m.removedAt is null
             order by m.joinedAt asc, m.id asc
            """)
    List<ChatRoomMember> findLiveMembershipsOf(@Param("userId") Long userId);

    /**
     * 이 방에서의 <b>살아 있는</b> 내 멤버십과 그 방 — 인가 한 번에 방 한 행까지(이슈 #79).
     *
     * <p>네 엔드포인트의 인가가 전부 이 조회 하나로 답한다. {@code removed_at} 조건이 여기
     * 있는 것이 요점이다 — 강퇴된 사람의 행은 남아 있으므로(행을 지우지 않는다) "행이 있는가"
     * 로 묻는 검사는 강퇴된 사람을 통과시킨다.
     *
     * <p>방을 함께 읽는 이유는 {@code last_seq} 다. ETag({@code "{roomId}:{lastSeq}"})와
     * 미읽음 뺄셈이 둘 다 그 값을 쓰는데, 인가와 따로 읽으면 쿼리가 하나 더 나간다.
     * 폴링 경로라 그 하나가 그대로 초당 부하가 된다.
     */
    @Query("""
            select m from ChatRoomMember m
              join fetch m.room r
             where r.id = :roomId
               and m.userId = :userId
               and m.removedAt is null
            """)
    Optional<ChatRoomMember> findLiveMembershipWithRoom(
            @Param("roomId") Long roomId, @Param("userId") Long userId);

    /**
     * 여러 방의 살아 있는 멤버 수를 한 문장으로 — 방 목록의 {@code memberCount}(이슈 #79).
     *
     * <p>{@link #countByRoomIdAndRemovedAtIsNull} 를 방마다 부르면 방 20개에 쿼리가 20개다.
     *
     * @return {@code [roomId, count]} 쌍. <b>멤버가 0인 방은 줄이 없다</b> — 부르는 쪽이
     *         기본값을 채운다
     */
    @Query("""
            select m.room.id, count(m) from ChatRoomMember m
             where m.room.id in :roomIds
               and m.removedAt is null
             group by m.room.id
            """)
    List<Object[]> countLiveMembersOfRooms(@Param("roomIds") Collection<Long> roomIds);

    /**
     * 읽음 워터마크를 올린다. <b>뒤로 가지 않고, 방의 끝을 넘지 않는다</b> — 이슈 #79
     * 완료 조건 4·7, 근거 ADR-0011 결정 3.
     *
     * <h2>왜 자바에서 비교하고 대입하지 않는가</h2>
     * <p>읽어서 비교하고 쓰면 두 문장 사이가 열린다 — 같은 사람의 두 기기가 동시에 읽음을
     * 보내면 둘 다 "지금 값은 5" 를 읽고 뒤에 쓴 쪽이 이긴다. 그게 하필 작은 값이면
     * 워터마크가 뒤로 간다(📌 #86 원칙 5 — 확인-후-쓰기는 DB 로 받친다).
     * {@code GREATEST} 를 <b>같은 문장 안</b>에 두면 계산 시점과 쓰기 시점이 갈라지지 않는다.
     *
     * <h2>{@code LEAST(:seq, r.last_seq)} 가 없으면 미읽음이 음수가 된다</h2>
     * <p>앱은 낙관적으로 커서를 올린다 — 방금 보낸 메시지의 번호를 미리 쓰거나, 재시도로
     * 예전 값을 다시 보낸다. 상한이 없으면 {@code last_read_seq} 가 {@code last_seq} 를 넘고,
     * 미읽음이 뺄셈이므로 뱃지에 음수가 뜬다. 그래서 <b>조인</b>이 필요하다: 상한은 이 방의
     * 현재 마지막 번호이고 그 값은 {@code chat_room} 에 있다.
     *
     * <p>네이티브 SQL 인 이유는 두 표를 함께 UPDATE 하기 때문이다(JPQL 의 {@code update} 는
     * 조인을 못 쓴다). 조인 대상은 {@code chat_room_member}·{@code chat_room} 둘뿐이라
     * 경계 안이다.
     *
     * <p>{@code removed_at is null} 이 여기에도 있다. 인가는 부르는 쪽이 이미 했지만, 이
     * 문장 하나만 봐도 강퇴된 사람의 커서가 움직이지 않아야 한다 — 조건이 한쪽에만 있으면
     * 다음 사람이 인가를 옮길 때 조용히 새는 자리가 된다.
     *
     * @return 1 이면 갱신을 시도했고(값이 그대로일 수도 있다), 0 이면 그런 살아 있는 멤버가 없다
     */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query(value = """
            update chat_room_member m
              join chat_room r on r.id = m.room_id
               set m.last_read_seq = GREATEST(m.last_read_seq, LEAST(:seq, r.last_seq))
             where m.room_id = :roomId
               and m.user_id = :userId
               and m.removed_at is null
            """, nativeQuery = true)
    int raiseReadWatermark(@Param("roomId") Long roomId,
                           @Param("userId") Long userId,
                           @Param("seq") long seq);

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
