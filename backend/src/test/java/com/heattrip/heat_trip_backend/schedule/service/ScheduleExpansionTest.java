package com.heattrip.heat_trip_backend.schedule.service;

import com.heattrip.heat_trip_backend.schedule.entity.Schedule;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleRepeat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 규칙을 날짜로 펼치는 규칙 — 이슈 #421.
 *
 * <h2>왜 통합 테스트로는 부족한가</h2>
 * <p>여기서 틀리는 자리는 <b>윤년·말일·주 경계</b>인데, 그것을 통합 테스트로만 재려면
 * 날짜마다 DB 와 인가를 함께 세워야 한다. 그러면 몇 개 못 재고, 못 잰 날짜가 언젠가
 * 사용자의 달력에서 하루 어긋난다.
 */
class ScheduleExpansionTest {

    private static Schedule rule(String start, ScheduleRepeat repeat, String until) {
        return Schedule.builder()
                .ownerKind(ScheduleOwnerKind.GROUP)
                .ownerRef(1L)
                .kind(ScheduleKind.MED)
                .title("심장사상충")
                .onDate(LocalDate.parse(start))
                .repeatKind(repeat)
                .repeatUntil(until == null ? null : LocalDate.parse(until))
                .build();
    }

    private static java.util.List<LocalDate> dates(Schedule rule, String from, String to) {
        return ScheduleExpansion.datesOf(
                rule, LocalDate.parse(from), LocalDate.parse(to), Set.of());
    }

    @Test
    @DisplayName("되풀이가 아니면 시작일 하루뿐이다")
    void nonRepeatingIsOneDay() {
        assertThat(dates(rule("2026-12-10", ScheduleRepeat.NONE, null), "2026-12-01", "2026-12-31"))
                .containsExactly(LocalDate.parse("2026-12-10"));
    }

    @Test
    @DisplayName("시작일 전에는 안 온다 — 기간이 그보다 앞이어도")
    void nothingBeforeTheStart() {
        assertThat(dates(rule("2026-12-10", ScheduleRepeat.DAILY, null), "2026-12-01", "2026-12-12"))
                .containsExactly(LocalDate.parse("2026-12-10"), LocalDate.parse("2026-12-11"),
                        LocalDate.parse("2026-12-12"));
    }

    @Test
    @DisplayName("매주는 시작일의 요일을 따른다")
    void weeklyFollowsTheStartWeekday() {
        // 2026-12-01 은 화요일.
        assertThat(dates(rule("2026-12-01", ScheduleRepeat.WEEKLY, null), "2026-12-01", "2026-12-31"))
                .containsExactly(
                        LocalDate.parse("2026-12-01"), LocalDate.parse("2026-12-08"),
                        LocalDate.parse("2026-12-15"), LocalDate.parse("2026-12-22"),
                        LocalDate.parse("2026-12-29"));
    }

    @Test
    @DisplayName("2월 29일 규칙은 평년을 통째로 건너뛴다 — 3월 1일로 밀지 않는다")
    void aLeapDayRuleSkipsCommonYears() {
        Schedule leap = rule("2028-02-29", ScheduleRepeat.MONTHLY, null);

        assertThat(dates(leap, "2029-02-01", "2029-02-28"))
                .as("2029년 2월에는 29일이 없다 — 사용자가 안 정한 날에 알림이 오면 안 된다")
                .isEmpty();
        assertThat(dates(leap, "2032-02-01", "2032-02-29"))
                .containsExactly(LocalDate.parse("2032-02-29"));
    }

    @Test
    @DisplayName("종료일 뒤로는 안 오고, 종료일 당일은 온다")
    void theEndDateIsInclusive() {
        Schedule until = rule("2026-12-01", ScheduleRepeat.DAILY, "2026-12-03");

        assertThat(dates(until, "2026-12-01", "2026-12-31"))
                .containsExactly(LocalDate.parse("2026-12-01"), LocalDate.parse("2026-12-02"),
                        LocalDate.parse("2026-12-03"));
    }

    @Test
    @DisplayName("예외로 적힌 날은 빠진다 — 건너뛴 날이든 옮긴 날이든 같다")
    void exceptionsDropTheirDays() {
        Schedule daily = rule("2026-12-01", ScheduleRepeat.DAILY, "2026-12-04");

        assertThat(ScheduleExpansion.datesOf(daily,
                LocalDate.parse("2026-12-01"), LocalDate.parse("2026-12-04"),
                Set.of(LocalDate.parse("2026-12-02"), LocalDate.parse("2026-12-03"))))
                .containsExactly(LocalDate.parse("2026-12-01"), LocalDate.parse("2026-12-04"));
    }

    @Test
    @DisplayName("기간이 규칙보다 좁으면 그 안만 준다 — 무한 규칙이 안전한 이유")
    void therangeBoundsAnEndlessRule() {
        Schedule endless = rule("2020-01-01", ScheduleRepeat.DAILY, null);

        assertThat(dates(endless, "2026-12-01", "2026-12-03")).hasSize(3);
    }
}
