package com.heattrip.heat_trip_backend.push;

import com.heattrip.heat_trip_backend.chat.ChatMessagePosted;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * 기기로 나가는 알림 하나 — 제목·본문과 앱이 열 자리를 가리키는 데이터.
 *
 * <p>본문은 미리보기다. 메시지 전문은 싣지 않는다 — 알림 센터는 잠금 화면에 그대로 보이고,
 * 기기 밖(FCM·APNs)을 지나는 것이라 짧을수록 좋다. 앱은 {@code data} 의 방 id 로 방을 열고
 * 전문은 서버에서 받는다.
 */
public record PushMessage(String title, String body, Map<String, String> data) {

    /** 잠금 화면에 보이는 미리보기 길이. */
    static final int PREVIEW_LENGTH = 80;

    public static PushMessage forChat(ChatMessagePosted event) {
        Map<String, String> data = new LinkedHashMap<>();
        data.put("kind", "chat.message");
        data.put("roomId", String.valueOf(event.roomId()));
        data.put("roomSeq", String.valueOf(event.roomSeq()));
        data.put("messageId", String.valueOf(event.messageId()));
        String preview = event.preview() == null ? "" : event.preview().strip();
        if (preview.length() > PREVIEW_LENGTH) {
            preview = preview.substring(0, PREVIEW_LENGTH) + "…";
        }
        String body = preview.isEmpty()
                ? event.senderName() + "님이 메시지를 보냈어요"
                : event.senderName() + ": " + preview;
        return new PushMessage(event.roomName(), body, Map.copyOf(data));
    }
}
