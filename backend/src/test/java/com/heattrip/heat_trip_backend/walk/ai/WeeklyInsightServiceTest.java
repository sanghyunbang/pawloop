package com.heattrip.heat_trip_backend.walk.ai;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/** 하루 상한 세기 — 이슈 #486. 서버 하나의 메모리 카운터라 값으로 잰다. */
class WeeklyInsightServiceTest {

    @Test
    @DisplayName("하루 상한까지만 허락하고, 날이 바뀌면 0 부터 다시 센다")
    void capsPerDayAndResetsAtMidnight() {
        WeeklyInsightService.DailyCounter counter = new WeeklyInsightService.DailyCounter();
        LocalDate today = LocalDate.of(2026, 9, 14);

        assertThat(counter.tryAcquire(today, 2)).isTrue();
        assertThat(counter.tryAcquire(today, 2)).isTrue();
        assertThat(counter.tryAcquire(today, 2)).as("셋째는 상한 — 조용히 1단계 문장만").isFalse();

        assertThat(counter.tryAcquire(today.plusDays(1), 2)).as("다음 날은 다시 부른다").isTrue();
    }

    @Test
    @DisplayName("상한 0 이면 한 번도 부르지 않는다 — 비용 스위치")
    void zeroCapNeverCalls() {
        WeeklyInsightService.DailyCounter counter = new WeeklyInsightService.DailyCounter();

        assertThat(counter.tryAcquire(LocalDate.of(2026, 9, 14), 0)).isFalse();
    }
}
