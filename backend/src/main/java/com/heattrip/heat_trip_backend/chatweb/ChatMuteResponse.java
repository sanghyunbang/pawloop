package com.heattrip.heat_trip_backend.chatweb;

/** 계약의 {@code RoomMute}. 서버가 실제로 쓴 값을 돌려준다. */
public record ChatMuteResponse(long roomId, boolean muted) {
}
