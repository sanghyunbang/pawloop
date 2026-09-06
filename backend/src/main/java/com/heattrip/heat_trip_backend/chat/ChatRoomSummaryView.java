package com.heattrip.heat_trip_backend.chat;

/**
 * 방 목록 한 줄 — 방 하나와 <b>나에게만 해당하는 값들</b>을 함께 든다. 이슈 #79.
 *
 * <h2>{@link #unread} 가 뺄셈인 것이 이 레코드의 요점이다</h2>
 * <p>{@code room.last_seq − member.last_read_seq}. 읽음 표를 따로 두지 않고, 미읽음을 세는
 * {@code COUNT} 도 돌리지 않는다 — 두 값 모두 방 목록 조회가 <b>이미 읽어 오는 컬럼</b>이라
 * 추가 쿼리가 0이다(ADR-0011 · 이슈 #79). 방이 20개면 COUNT 판은 쿼리가 21개다.
 *
 * <p><b>여기서 음수를 잘라 내지 않는다.</b> 자르면 워터마크의 상한
 * ({@code LEAST(:seq, room.last_seq)})이 사라져도 아무도 모른다 — 그 상한이 사라지면
 * {@code last_read_seq} 가 {@code last_seq} 를 넘고, 그 사고가 보이는 자리가 정확히 이
 * 뺄셈이다. 자르는 것은 증상을 가리는 것이라 쓰기 쪽에서 막는다
 * ({@link ChatRoomService#markRead}).
 *
 * <p>{@link #lastMessage} 는 방마다 따로 조회하지 않는다. 마지막 메시지는
 * {@code room_seq = room.last_seq} 인 행이라 방 목록 전체를 <b>한 문장</b>으로 모을 수 있다
 * ({@code ChatMessageRepository#findLastMessagesOfRooms}).
 *
 * @param myRole      이 방에서 <b>내</b> 역할. {@code OWNER}/{@code MEMBER} 문자열인 이유는
 *                    {@link ChatMemberView} 와 같다 — enum 은 {@code chat.entity} 에 산다
 * @param lastMessage 아직 아무 말도 없는 방이면 {@code null}
 */
public record ChatRoomSummaryView(
        ChatRoomView room,
        String myRole,
        long lastReadSeq,
        long unread,
        int memberCount,
        ChatMessageView lastMessage,
        boolean muted) {
}
