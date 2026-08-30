package com.heattrip.heat_trip_backend.chat;

import java.time.LocalDateTime;

/**
 * 살아 있는 방 멤버 하나를 chat 밖으로 내보내는 모양 — 이슈 #75.
 *
 * <p><b>{@code role} 이 enum 이 아니라 문자열인 것은 의도다.</b> {@code ChatRoomMemberRole} 은
 * {@code chat.entity} 에 살고, 그 패키지를 밖에서 이름으로 부르는 순간 경계가 한 겹 얇아진다.
 * 밖이 이 값으로 하는 일은 그대로 JSON 에 싣는 것뿐이라({@code OWNER}/{@code MEMBER}) 타입이
 * 있어서 얻는 것이 없다.
 *
 * <p>{@code nickname} 이 없는 것도 의도다 — 그건 {@code users} 의 값이고 chat 은 사용자를
 * id 로만 안다(ADR-0011 결정 4). 이름을 붙이는 것은 부르는 쪽의 일이다.
 */
public record ChatMemberView(
        long userId,
        String role,
        long lastReadSeq,
        LocalDateTime joinedAt) {
}
