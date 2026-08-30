package com.heattrip.heat_trip_backend.chat.entity;

/**
 * 방 안에서의 역할. ADR-0011 결정 6 — <b>강퇴·초대 회수는 {@link #OWNER} 만 한다.</b>
 *
 * <p>문자열로 저장한다({@code varchar(10)}). MySQL 네이티브 {@code enum} 을 쓰지 않는 이유는
 * 값이 늘어날 때 {@code ALTER TABLE} 이 필요해지기 때문이고, 대신 CHECK 제약이 값을 잠근다.
 */
public enum ChatRoomMemberRole {
    OWNER,
    MEMBER
}
