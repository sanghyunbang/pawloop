package com.heattrip.heat_trip_backend.chatweb;

/** {@code PUT /api/chat/rooms/{roomId}/mute} 의 본문. {@code muted} 가 없으면 400 — "{}" 가 해제로 읽히면 안 된다. */
public record ChatMuteRequest(Boolean muted) {

    boolean requireMuted() {
        if (muted == null) {
            throw new IllegalArgumentException("muted 값이 필요합니다.");
        }
        return muted;
    }
}
