package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatMessageView;

import java.time.LocalDateTime;

/**
 * 계약({@code openapi.yaml})의 {@code ChatMessage} 모양 — 이슈 #78.
 *
 * <h2>{@code senderName} 이 여기서 <b>바뀐다</b> — 그게 이 레코드가 있는 이유다</h2>
 * <p>{@link ChatMessageView#senderNameAtSendTime()} 는 <b>보낸 시점의 스냅샷</b>이고,
 * 계약의 {@code senderName} 은 <b>지금 {@code users} 에 있는 이름</b>이다(#78 완료 조건 3·4 —
 * 닉네임을 바꾸면 과거 메시지도 따라 바뀌고, 탈퇴하면 "알 수 없음" 이다). 두 값이 같은
 * 이름으로 불리면 옮기는 자리에서 반드시 한 번은 헷갈린다. 그래서 chat 쪽 필드에는 시제를
 * 박아 두었고, 계약의 이름으로 되돌리는 것은 여기 한 곳이다.
 *
 * <p>{@link #of(ChatMessageView, String)} 가 이름을 <b>인자로 받는</b> 것도 같은 이유다 —
 * 이 레코드는 {@code users} 를 모르고, 이름을 만드는 것은 {@link ChatSenderNames} 다.
 *
 * <h2>{@code clientMsgId} 를 싣지 않는다</h2>
 * <p>계약의 {@code ChatMessage} 스키마에 없다. 멱등키는 클라이언트가 만들어 보낸 값이라
 * 돌려줄 이유가 없고, 실으면 같은 방의 다른 사람에게 남의 키가 보인다.
 *
 * @param deletedAt 소프트 삭제 시각. <b>{@code null} 이 아니어도 목록에서 빠지지 않는다</b> —
 *                  톰스톤이다. 본문을 가리는 것은 화면의 일이다(ADR-0011)
 */
public record ChatMessageResponse(
        long id,
        long roomId,
        long roomSeq,
        long senderUserId,
        String senderName,
        String contentType,
        String body,
        LocalDateTime createdAt,
        LocalDateTime deletedAt) {

    static ChatMessageResponse of(ChatMessageView message, String senderName) {
        return new ChatMessageResponse(message.id(), message.roomId(), message.roomSeq(),
                message.senderUserId(), senderName, message.contentType(), message.body(),
                message.createdAt(), message.deletedAt());
    }
}
