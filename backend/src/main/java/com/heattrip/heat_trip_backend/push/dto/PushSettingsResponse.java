package com.heattrip.heat_trip_backend.push.dto;

/** 계약의 {@code PushSettings}. 방별 음소거는 방 목록({@code ChatRoom.muted})에 실린다. */
public record PushSettingsResponse(boolean enabled) {
}
