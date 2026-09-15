package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

/**
 * 메시지 저장·조회 — 이슈 #78.
 *
 * <h2>커서는 {@code room_seq} 다. {@code id} 가 아니다</h2>
 * <p>이 인터페이스에 {@code findByIdGreaterThan…} 류가 없는 것이 그 뜻이다.
 * {@code AUTO_INCREMENT} 는 배정 시점에 정해지고 가시성은 커밋 시점에 생기므로,
 * {@code id} 커서는 늦게 커밋된 작은 {@code id} 를 <b>영구히</b> 건너뛴다
 * (ADR-0011 결정 2 · {@link ChatMessage} javadoc).
 *
 * <p>정렬과 범위 조건이 둘 다 {@code (room_id, room_seq)} 라 {@code UNIQUE
 * (room_id, room_seq)} 인덱스의 범위 스캔으로 끝난다 — 정렬을 위한 filesort 가 없다.
 *
 * <h2>삭제된 메시지를 거르지 않는다</h2>
 * <p>{@code deleted_at is null} 을 여기 붙이고 싶어지는 자리인데, 붙이면 그 {@code room_seq}
 * 가 클라이언트에 도달하지 않는다. 미읽음이 {@code room.last_seq − member.last_read_seq}
 * 뺄셈이라 읽음 커서가 그 번호를 넘지 못하고 <b>뱃지가 영원히 안 지워진다</b>(ADR-0011).
 * 조회는 톰스톤을 그대로 돌려주고, 본문을 가리는 것은 응답을 만드는 쪽의 일이다.
 */
public interface ChatMessageRepository extends JpaRepository<ChatMessage, Long> {

    /**
     * 이 방에서 {@code afterSeq} 다음 메시지들 — {@code room_seq} 오름차순.
     *
     * <p>#79 의 델타 폴링이 쓸 모양이고, 이 이슈에서는 완료 조건 3·4 를 확인하는 데 쓴다.
     * {@code Limit} 는 스프링 데이터 6.1 의 방식이다 — {@code Pageable} 을 쓰면 안 쓰는
     * {@code count} 쿼리와 {@code Page} 포장이 함께 온다.
     */
    List<ChatMessage> findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(
            Long roomId, long afterSeq, Limit limit);

    /**
     * 이 방에서 {@code beforeSeq} <b>앞의</b> 메시지들 — {@code room_seq} 내림차순.
     *
     * <p>과거 스크롤과 <b>첫 진입</b>이 같은 문장을 쓴다. 첫 진입은 "최신 N 건" 인데, 그것은
     * {@code beforeSeq} 를 방의 끝보다 큰 값으로 두는 것과 같다 — 두 경로를 하나로 두면
     * 페이지 계산이 한 벌이다.
     *
     * <p>내림차순인 것은 <b>인덱스 때문</b>이다. {@code UNIQUE (room_id, room_seq)} 를 뒤에서부터
     * 훑어 {@code limit} 개만 읽는다. 오름차순으로 읽고 자바에서 마지막 N 개를 고르면 방
     * 전체를 읽는다. 부르는 쪽이 뒤집어 오름차순으로 내보낸다 —
     * 응답의 순서는 어느 방향으로 넘겼든 하나여야 한다({@code ChatMessagePageView}).
     */
    List<ChatMessage> findByRoomIdAndRoomSeqLessThanOrderByRoomSeqDesc(
            Long roomId, long beforeSeq, Limit limit);

    /**
     * 여러 방의 <b>마지막 메시지</b>를 한 문장으로 — 방 목록의 미리보기(이슈 #79).
     *
     * <p>방마다 따로 조회하면 방 20개에 쿼리가 21개다. 폴링이 아니라 목록 진입이지만 홈
     * 화면이 열릴 때마다 도는 경로라 그 곱셈을 두지 않는다.
     *
     * <p><b>{@code room_seq = room.last_seq} 로 찾는 것이 핵심이다.</b> {@code max(room_seq)}
     * 를 방마다 구하는 서브쿼리 대신, 이미 방 행에 있는 발급 카운터를 그대로 쓴다. 그 값이
     * 곧 마지막 메시지의 번호인 이유는 발급과 INSERT 가 한 트랜잭션이고 실패하면 번호가
     * 함께 되돌아가기 때문이다({@code ChatRoomRepository#assignNextSeq}). 아직 아무 말도
     * 없는 방은 {@code last_seq = 0} 이라 이 조회에 걸리지 않는다.
     *
     * <p>삭제된 메시지를 거르지 않는다. 마지막 말이 지워진 방의 미리보기를 어떻게 그릴지는
     * 화면의 일이고({@code deletedAt} 이 실린다), 여기서 거르면 그 방만 미리보기가 통째로
     * 사라져 "말이 없는 방" 처럼 보인다.
     */
    @Query("""
            select m from ChatMessage m
              join m.room r
             where r.id in :roomIds
               and m.roomSeq = r.lastSeq
            """)
    List<ChatMessage> findLastMessagesOfRooms(@Param("roomIds") Collection<Long> roomIds);

    /**
     * <b>같은 사람이</b> 같은 방에 같은 멱등키로 이미 넣어 둔 메시지.
     *
     * <p>이 조회는 <b>판정이 아니다.</b> 중복을 막는 것은 {@code UNIQUE (room_id,
     * sender_user_id, client_msg_id)} 이고(📌 #86 원칙 5), 이것은 진 쪽이 "그래서 이미
     * 있는 그 메시지가 무엇인가" 를 답하기 위한 조회다. 재전송을 200 으로 돌려주는 경로는
     * {@code ChatMessageSender} 다.
     *
     * <p><b>{@code senderUserId} 가 조건에 있는 것이 요점이다.</b> 빼면 같은 방의 다른
     * 멤버가 같은 키를 썼을 때 <b>남의 메시지</b>를 "당신이 아까 보낸 그것" 이라며
     * 돌려주게 된다 — #79 이전 판이 실제로 그랬다. 제약과 이 조회의 범위는 같아야 한다.
     */
    /**
     * 신고가 고른 메시지들을 한 번에 읽는다 — 이슈 #82.
     *
     * <p><b>{@code room_seq} 로 찾는 이유</b>: 앱이 들고 있는 좌표가 그것이다. {@code id} 는
     * 방을 넘나드는 전역 번호라 "이 방의 3번" 을 표현하지 못하고, 커서가 {@code room_seq} 인
     * 이 도메인에서 신고만 다른 좌표를 쓰면 앱이 두 가지를 들고 다녀야 한다
     * ({@code ChatMessage} javadoc).
     *
     * <p>{@code UNIQUE (room_id, room_seq)} 가 선두 컬럼 인덱스라 이 조회가 그것을 쓴다.
     *
     * <p>못 찾은 seq 는 그냥 빠져서 온다 — 개수가 맞는지는 부르는 쪽이 본다.
     */
    List<ChatMessage> findByRoomIdAndRoomSeqIn(Long roomId, Collection<Long> roomSeqs);

    /**
     * 답장의 원문들을 한 번에 — 이슈 #452. <b>같은 방 안에서만</b> 찾는다: 남의 방 메시지 id 를
     * 들이밀어도 안 나온다. 지워진 것도 준다(미리보기가 "삭제된 메시지" 를 그린다).
     */
    List<ChatMessage> findByRoomIdAndIdIn(Long roomId, Collection<Long> ids);

    /**
     * 이 방에서 {@code afterChangeSeq} 뒤에 <b>바뀐</b> 말들 — ADR-0023(#500). 변경 번호 오름차순.
     *
     * <p>{@code roomSeq > minRoomSeq} 로 창을 좁히는 것이 요점이다. 방을 오래 열어 둔 사람에게 1년 치 변경을
     * 내려보내지 않기 위해서고, 그 범위 밖의 변화는 방을 다시 열 때 장(page) 조회가 가져온다.
     *
     * <p>{@code (room_id, change_seq)} 인덱스({@code idx_chat_change})의 범위 스캔이다 — 한 번도 안 바뀐 말은
     * {@code change_seq} 가 NULL 이라 인덱스에서 이 조건에 걸리지 않는다.
     */
    @Query("""
            select m from ChatMessage m
             where m.room.id = :roomId
               and m.changeSeq > :afterChangeSeq
               and m.roomSeq > :minRoomSeq
             order by m.changeSeq asc
            """)
    List<ChatMessage> findChangedAfter(@Param("roomId") Long roomId,
                                       @Param("afterChangeSeq") long afterChangeSeq,
                                       @Param("minRoomSeq") long minRoomSeq,
                                       Limit limit);

    Optional<ChatMessage> findByRoomIdAndSenderUserIdAndClientMsgId(
            Long roomId, Long senderUserId, String clientMsgId);
}
