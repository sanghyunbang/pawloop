package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;

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
     * 같은 방에 같은 멱등키로 이미 들어온 메시지.
     *
     * <p>이 조회는 <b>판정이 아니다.</b> 중복을 막는 것은 {@code UNIQUE (room_id,
     * client_msg_id)} 이고(📌 #86 원칙 5), 이것은 진 쪽이 "그래서 이미 있는 그 메시지가
     * 무엇인가" 를 답하기 위한 조회다. 재전송을 200 으로 돌려주는 경로는 #79 다.
     */
    Optional<ChatMessage> findByRoomIdAndClientMsgId(Long roomId, String clientMsgId);
}
