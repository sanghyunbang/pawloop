package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatRoomView;

import java.time.LocalDateTime;

/**
 * 계약({@code openapi.yaml})의 {@code ChatRoom} 모양 — 이슈 #75.
 *
 * <p><b>{@code ChatRoomView} 를 그대로 내보내지 않는 이유는 이름 하나다.</b> 계약은 방 이름을
 * {@code title} 이라 부르고 chat 은 {@code name} 이라 부른다. 여기서 옮기지 않으면 계약과
 * 실제 응답이 갈리고, 앱은 계약을 보고 만든다.
 *
 * <p>계약의 {@code ChatRoom} 에 있는 나머지 필드({@code unread} · {@code lastReadSeq} ·
 * {@code myRole} · {@code lastMessage})는 <b>일부러 비웠다.</b> 미읽음 뺄셈과 메시지는 #77~#79
 * 가 만든다. 지금 0 이나 {@code null} 을 실어 보내면 앱은 "값이 있다" 고 읽는다.
 */
public record ChatRoomResponse(
        long id,
        String title,
        String tag,
        String originKind,
        String originRef,
        long lastSeq,
        int memberCount,
        LocalDateTime createdAt) {

    static ChatRoomResponse of(ChatRoomView room, int memberCount) {
        return new ChatRoomResponse(room.id(), room.name(), room.tag(),
                room.originKind(), room.originRef(), room.lastSeq(), memberCount, room.createdAt());
    }
}
