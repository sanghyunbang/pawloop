package com.heattrip.heat_trip_backend.walk.ai;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;

import static org.assertj.core.api.Assertions.assertThat;

/** 하루 상한 세기 — 이슈 #486 · #538. 서버 하나의 메모리 카운터라 값으로 잰다. */
class WeeklyInsightServiceTest {

    @Nested
    @DisplayName("서버 전체 하루 상한")
    class WholeServer {

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

    /**
     * 요약 하나의 하루 상한 — #538. 예전에는 <b>주당 세 번</b>이었고, 닿으면 옛 문장을 그대로
     * 내보내 카드가 틀린 숫자를 말했다. 지금은 날 단위이고, 닿으면 카드를 안 그린다.
     */
    @Nested
    @DisplayName("요약 하나의 하루 상한")
    class PerRow {

        private static final LocalDate TODAY = LocalDate.of(2026, 9, 15);
        private static final String BORI = "19:7:2026-09-14";
        private static final String NURI = "19:8:2026-09-14";

        @Test
        @DisplayName("한 요약이 상한까지만 쓴다")
        void capsOneRow() {
            WeeklyInsightService.PerRowDailyCounter counter = new WeeklyInsightService.PerRowDailyCounter();

            assertThat(counter.tryAcquire(TODAY, BORI, 2)).isTrue();
            assertThat(counter.tryAcquire(TODAY, BORI, 2)).isTrue();
            assertThat(counter.tryAcquire(TODAY, BORI, 2)).as("셋째는 상한").isFalse();
        }

        @Test
        @DisplayName("요약이 다르면 몫도 다르다 — 한 사람이 남의 몫을 안 쓴다")
        void keysDoNotShareTheirQuota() {
            WeeklyInsightService.PerRowDailyCounter counter = new WeeklyInsightService.PerRowDailyCounter();

            assertThat(counter.tryAcquire(TODAY, BORI, 1)).isTrue();
            assertThat(counter.tryAcquire(TODAY, BORI, 1)).isFalse();
            assertThat(counter.tryAcquire(TODAY, NURI, 1))
                    .as("보리가 다 썼다고 누리가 못 쓰면, 이 상한이 서버 상한과 같은 것이 된다").isTrue();
        }

        @Test
        @DisplayName("날이 바뀌면 0 부터 다시 센다 — 그 주가 끝날 때까지 굳지 않는다 (#538)")
        void resetsAtMidnight() {
            WeeklyInsightService.PerRowDailyCounter counter = new WeeklyInsightService.PerRowDailyCounter();

            assertThat(counter.tryAcquire(TODAY, BORI, 1)).isTrue();
            assertThat(counter.tryAcquire(TODAY, BORI, 1)).isFalse();

            assertThat(counter.tryAcquire(TODAY.plusDays(1), BORI, 1))
                    .as("예전 상한은 주 단위라, 화요일에 닿으면 일요일까지 문장이 굳었다").isTrue();
        }

        @Test
        @DisplayName("상한 0 이면 한 번도 부르지 않는다")
        void zeroCapNeverCalls() {
            WeeklyInsightService.PerRowDailyCounter counter = new WeeklyInsightService.PerRowDailyCounter();

            assertThat(counter.tryAcquire(TODAY, BORI, 0)).isFalse();
        }
    }
}
