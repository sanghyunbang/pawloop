package com.heattrip.heat_trip_backend.group.dto;

import java.time.LocalDateTime;

/**
 * 가족 그룹 멤버 하나 — 계약({@code openapi.yaml})의 {@code GroupMember} 다.
 *
 * <p><b>이 값은 {@code group_member} 표에서 오지 않는다. 그런 표는 없다.</b>
 * {@code chat_room_member} 한 줄을 가족 그룹의 언어로 다시 적은 것이다(ADR-0011 결정 1).
 * 계약이 예전에 그리던 {@code group_member} 를 이 이슈가 정리했다.
 *
 * @param role     {@code OWNER} 또는 {@code MEMBER}. {@code chat_room_member.role} 그대로다 —
 *                 소문자 {@code owner}/{@code member} 로 다시 적으면 같은 값에 표기가 둘이 된다
 * @param nickname {@code users} 의 현재 닉네임. 탈퇴했으면 {@code 알 수 없음} 이다 —
 *                 chat 은 사용자를 id 로만 알므로 이름을 붙이는 것은 이 모듈의 일이다
 */
public record GroupMemberResponse(
        long userId,
        String nickname,
        String role,
        LocalDateTime joinedAt) {
}
