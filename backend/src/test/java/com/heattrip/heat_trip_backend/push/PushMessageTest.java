package com.heattrip.heat_trip_backend.push;

import com.heattrip.heat_trip_backend.schedule.ScheduleAssigned;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalTime;

import static org.assertj.core.api.Assertions.assertThat;

/** 배정 알림 한 줄의 문구 — 이슈 #735. 순수 함수라 컨텍스트 없이 잰다. */
class PushMessageTest {

    private static final LocalDate TODAY = LocalDate.of(2026, 9, 20);

    private static ScheduleAssigned assigned(String dogName, LocalDate onDate, LocalTime atTime) {
        return new ScheduleAssigned(41L, 6L, 5L, "엄마", "병원", dogName, onDate, atTime);
    }

    @Test
    @DisplayName("제목은 누가, 본문은 언제 · 아이 · 제목 — 내일 10:30 · 뭉치 병원")
    void titleIsWhoAndBodyIsWhenAndWhat() {
        PushMessage m = PushMessage.forScheduleAssigned(
                assigned("뭉치", TODAY.plusDays(1), LocalTime.of(10, 30)), TODAY);

        assertThat(m.title()).isEqualTo("엄마님이 일정을 맡겼어요");
        assertThat(m.body()).isEqualTo("내일 10:30 · 뭉치 병원");
        assertThat(m.data()).containsEntry("kind", "schedule.assigned")
                .containsEntry("scheduleId", "41")
                .containsEntry("onDate", "2026-09-21");
    }

    @Test
    @DisplayName("오늘 · 내일 · 모레는 말로, 그 뒤는 날짜로 — 지난 날짜도 날짜로")
    void relativeDayLabels() {
        assertThat(PushMessage.whenLabel(TODAY, TODAY)).isEqualTo("오늘");
        assertThat(PushMessage.whenLabel(TODAY.plusDays(1), TODAY)).isEqualTo("내일");
        assertThat(PushMessage.whenLabel(TODAY.plusDays(2), TODAY)).isEqualTo("모레");
        assertThat(PushMessage.whenLabel(TODAY.plusDays(3), TODAY)).isEqualTo("9월 23일");
        assertThat(PushMessage.whenLabel(TODAY.minusDays(1), TODAY)).isEqualTo("9월 19일");
    }

    @Test
    @DisplayName("하루 종일이면 시각이 없고, 아이가 없으면 제목만")
    void allDayAndNoDog() {
        PushMessage m = PushMessage.forScheduleAssigned(assigned(null, TODAY, null), TODAY);

        assertThat(m.body()).isEqualTo("오늘 · 병원");
        assertThat(m.body()).doesNotContain("00:00");
    }
}
