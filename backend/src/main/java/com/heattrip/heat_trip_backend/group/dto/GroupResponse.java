package com.heattrip.heat_trip_backend.group.dto;

import java.time.Instant;
import java.util.List;

/**
 * 가족 그룹 하나 — 계약({@code openapi.yaml})의 {@code Group} 이다. 이슈 #75.
 *
 * <p><b>{@code inviteCode} 가 없다.</b> 계약에 있던 그 필드는 ADR-0011 이 {@code chat_room_invite}
 * 로 옮겼고, 이 이슈가 계약에서도 걷어냈다. 초대코드는 그룹이 아니라 <b>방</b>에 붙고
 * 만료·사용횟수·회수를 가진다 — 발급은 {@code POST /api/chat/rooms/{roomId}/invites} 다.
 * 그룹 응답에 코드를 하나 실으면 "그룹당 코드 하나" 라는 옛 모양이 앱 화면에서 되살아난다.
 *
 * <p><b>{@code createdAt} 은 오프셋을 달고 나간다.</b> 계약이 {@code format: date-time}
 * 이라고 선언했고 그건 RFC3339 오프셋이 있어야 성립한다 — 앱은 오프셋 없는 문자열을
 * 기기 지역 시각으로 읽는다(#248). 컬럼 값은 UTC 다
 * ({@link com.heattrip.heat_trip_backend.chat.ChatTime}).
 *
 * @param roomId 이 그룹의 방. 초대 발급·회수·채팅이 전부 이 id 로 간다
 */
public record GroupResponse(
        long id,
        String name,
        long roomId,
        List<GroupMemberResponse> members,
        Instant createdAt) {
}
