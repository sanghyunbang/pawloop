package com.heattrip.heat_trip_backend.group.dto;

/**
 * {@code POST /api/groups} 의 본문 — 이슈 #75.
 *
 * <p>필드가 이름 하나뿐인 것은 계약 그대로다. 생성자가 {@code OWNER} 로 참여하는 것은
 * 토큰이 정하고, 초대코드는 여기서 만들지 않는다({@code GroupResponse} javadoc 참조).
 */
public record CreateGroupRequest(String name) {
}
