package com.heattrip.heat_trip_backend.walk.entity;

import com.heattrip.heat_trip_backend.user.entity.User;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/** 요약 행의 평가(#486 후속) — 문장이 다시 만들어지면 옛 문장에 대한 평가는 사라진다. 스프링 없음(#21). */
class WeeklyInsightTest {

    private static final LocalDateTime AT = LocalDateTime.of(2026, 9, 14, 9, 0);

    @Test
    @DisplayName("평가하면 값과 시각이 남고, null 로 지우면 시각도 함께 빈다")
    void rateAndClear() {
        WeeklyInsight row = WeeklyInsight.first(User.builder().build(), 0, LocalDate.of(2026, 9, 14), "h", "m", "문장", AT);

        row.rate(WeeklyInsight.FEEDBACK_UP, AT.plusHours(1));

        assertThat(row.getFeedback()).isEqualTo("up");
        assertThat(row.getFeedbackAt()).isEqualTo(AT.plusHours(1));

        row.rate(null, AT.plusHours(2));

        assertThat(row.getFeedback()).isNull();
        assertThat(row.getFeedbackAt()).isNull();
    }

    @Test
    @DisplayName("문장이 다시 만들어지면 평가가 지워진다 — 옛 문장에 대한 평가라서")
    void regenerationClearsTheFeedback() {
        WeeklyInsight row = WeeklyInsight.first(User.builder().build(), 0, LocalDate.of(2026, 9, 14), "h", "m", "문장", AT);
        row.rate(WeeklyInsight.FEEDBACK_DOWN, AT.plusHours(1));

        row.regenerated("h2", "m", "새 문장", AT.plusDays(1));

        assertThat(row.getFeedback()).isNull();
        assertThat(row.getFeedbackAt()).isNull();
        assertThat(row.getCalls()).isEqualTo(2);
    }
}
