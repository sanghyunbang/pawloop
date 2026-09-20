package com.heattrip.heat_trip_backend.push;

import com.heattrip.heat_trip_backend.chat.ChatMessagePosted;
import com.heattrip.heat_trip_backend.schedule.ScheduleAssigned;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
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

    private static final DateTimeFormatter TIME = DateTimeFormatter.ofPattern("HH:mm");

    /**
     * "엄마님이 일정을 맡겼어요 — 내일 10:30 · 뭉치 병원" (이슈 #735).
     *
     * <p>제목은 <b>누가</b>, 본문은 <b>언제 · 무엇</b>이다. 언제는 오늘·내일·모레까지는 말로,
     * 그 뒤는 날짜로 — 알림은 한 줄이라 "9월 21일" 보다 "내일" 이 빨리 읽힌다.
     *
     * @param today 받는 쪽의 오늘(KST). 발송 시점의 시계라 "내일" 이 사실이다
     */
    public static PushMessage forScheduleAssigned(ScheduleAssigned event, LocalDate today) {
        Map<String, String> data = new LinkedHashMap<>();
        data.put("kind", "schedule.assigned");
        data.put("scheduleId", String.valueOf(event.scheduleId()));
        data.put("onDate", event.onDate().toString());
        String when = whenLabel(event.onDate(), today)
                + (event.atTime() == null ? "" : " " + TIME.format(event.atTime()));
        String what = event.dogName() == null || event.dogName().isBlank()
                ? event.title()
                : event.dogName() + " " + event.title();
        return new PushMessage(event.actorName() + "님이 일정을 맡겼어요", when + " · " + what,
                Map.copyOf(data));
    }

    /** 오늘 · 내일 · 모레 · 그 뒤는 "M월 d일". 지난 날짜도 날짜로 — 지난 일을 맡길 수도 있다. */
    static String whenLabel(LocalDate onDate, LocalDate today) {
        long days = ChronoUnit.DAYS.between(today, onDate);
        if (days == 0) {
            return "오늘";
        }
        if (days == 1) {
            return "내일";
        }
        if (days == 2) {
            return "모레";
        }
        return onDate.getMonthValue() + "월 " + onDate.getDayOfMonth() + "일";
    }
}
