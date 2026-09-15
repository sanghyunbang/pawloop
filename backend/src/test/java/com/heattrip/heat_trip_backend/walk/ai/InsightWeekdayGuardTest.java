package com.heattrip.heat_trip_backend.walk.ai;

import com.heattrip.heat_trip_backend.walk.dto.WalkStatsResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 산책하지 않은 요일을 말하는 문장을 버린다 — 이슈 #543.
 *
 * <p>실제로 나왔던 문장이 첫 테스트다. 숫자 검사는 통과했다.
 */
class InsightWeekdayGuardTest {

    /** #543 에 적힌 그 주 — 화요일에만 걸었다. */
    private static final String INPUT = """
            이번 주(월요일 9월 8일 시작, 오늘은 화요일)
            - 이번 주 합계: 1.9km · 3회 · 2분
            - 요일별 km: 월 0, 화 1.9, 수 0, 목 0, 금 0, 토 0, 일 0
            - 시간대별 횟수: 새벽 0회, 아침 0회, 낮 3회, 저녁 0회
            - 지난주: 0km · 0회 · 0분
            """;

    @Test
    @DisplayName("실제로 나왔던 문장 — 월 0 인데 '월·화' 라고 했다")
    void rejectsTheSentenceThatShipped() {
        String text = "이번 주는 월·화에 낮 산책 3회로 1.9km, 2분을 기록했어요.";

        assertThat(InsightNumberGuard.allowed(text, INPUT))
                .as("숫자 검사는 통과한다 — 그래서 이 가드가 필요했다")
                .isTrue();
        assertThat(InsightWeekdayGuard.allowed(text, INPUT)).isFalse();
    }

    @Test
    @DisplayName("걸은 요일만 말하면 통과한다")
    void allowsTheDayThatWasWalked() {
        assertThat(InsightWeekdayGuard.allowed("화요일에 세 번 나갔어요.", INPUT)).isTrue();
        assertThat(InsightWeekdayGuard.allowed("이번 주는 화에만 걸었어요.", INPUT))
                .as("줄도 아니고 '요일' 도 안 붙은 홑 글자는 요일로 안 읽는다 — 겹치는 낱말이 너무 많다")
                .isTrue();
    }

    @Test
    @DisplayName("요일을 아예 안 말하는 문장도 통과한다")
    void allowsSentencesWithoutWeekdays() {
        assertThat(InsightWeekdayGuard.allowed("이번 주는 3회로 1.9km를 걸었어요.", INPUT)).isTrue();
        assertThat(InsightWeekdayGuard.allowed("", INPUT)).isTrue();
    }

    @Test
    @DisplayName("겹치는 낱말을 요일로 읽지 않는다 — 횟수 · 목표 · 3일 · 일주일")
    void doesNotReadOrdinaryWordsAsWeekdays() {
        // 이 문장의 "수" 와 "목" 은 앞뒤에 한글이 붙어 있다. 붙어 있으면 낱말의 일부다.
        assertThat(InsightWeekdayGuard.weekdaysIn("횟수, 목표를 3일 만에 채웠어요.")).isEmpty();
        assertThat(InsightWeekdayGuard.weekdaysIn("이번 주 목표는 150분이에요.")).isEmpty();
        assertThat(InsightWeekdayGuard.weekdaysIn("일주일에 세 번 나갔어요.")).isEmpty();
        assertThat(InsightWeekdayGuard.allowed("횟수, 목표를 3일 만에 채웠어요.", INPUT)).isTrue();
    }

    @Test
    @DisplayName("줄의 앞 테두리 — 앞 글자가 붙어 있으면 낱말의 일부다")
    void aRunGluedOnTheLeftIsNotWeekdays() {
        assertThat(InsightWeekdayGuard.weekdaysIn("횟수, 목에 무리가 왔어요."))
                .as("'횟수' 의 수다. 뒤 테두리만 보면 '목에' 의 '에' 가 조사라 통과한다")
                .isEmpty();
    }

    @Test
    @DisplayName("줄의 뒤 테두리 — 조사가 아닌 한글이 붙어 있으면 낱말의 일부다")
    void aRunGluedOnTheRightIsNotWeekdays() {
        assertThat(InsightWeekdayGuard.weekdaysIn("월, 목표를 세웠어요."))
                .as("'목표' 의 목이다. 앞 테두리만 보면 '월' 앞이 비어 있어 통과한다")
                .isEmpty();
        assertThat(InsightWeekdayGuard.weekdaysIn("월·화요."))
                .as("'요' 는 조사다")
                .containsExactly('월', '화');
    }

    @Test
    @DisplayName("'3일·월' 의 '일' 은 날수다 — 앞이 숫자면 요일 줄이 아니다")
    void digitBeforeADayCharIsACount() {
        assertThat(InsightWeekdayGuard.weekdaysIn("3일·월")).isEmpty();
        assertThat(InsightWeekdayGuard.weekdaysIn("3일 뒤 월요일")).containsExactly('월');
    }

    @Test
    @DisplayName("이음말 여러 모양을 요일 줄로 읽는다")
    void readsRunsOfDayCharacters() {
        assertThat(InsightWeekdayGuard.weekdaysIn("월·화")).containsExactly('월', '화');
        assertThat(InsightWeekdayGuard.weekdaysIn("월, 화, 수")).containsExactly('월', '화', '수');
        assertThat(InsightWeekdayGuard.weekdaysIn("화~목")).containsExactly('화', '목');
        assertThat(InsightWeekdayGuard.weekdaysIn("금/토")).containsExactly('금', '토');
        assertThat(InsightWeekdayGuard.weekdaysIn("이번 주는 월·화에 걸었어요."))
                .as("조사 '에' 가 붙어도 요일이다")
                .containsExactly('월', '화');
    }

    @Test
    @DisplayName("과 · 와 는 이음말이 아니다 — '횟수와 목표' 가 요일 줄로 읽혔다")
    void conjunctionParticlesAreNotJoiners() {
        assertThat(InsightWeekdayGuard.weekdaysIn("횟수와 목표")).isEmpty();
        assertThat(InsightWeekdayGuard.weekdaysIn("월과 화"))
                .as("이 모양은 못 잡는다 — 못 잡는 쪽으로 틀린다. 프롬프트가 먼저 막는다")
                .isEmpty();
        assertThat(InsightWeekdayGuard.weekdaysIn("월요일과 화요일"))
                .as("긴 모양은 잡는다")
                .containsExactly('월', '화');
    }

    @Test
    @DisplayName("근거가 없으면 요일을 말할 수 없다 — 요일별 줄이 없는 입력")
    void rejectsWeekdaysWhenTheInputHasNoWeekdayLine() {
        assertThat(InsightWeekdayGuard.allowed("월요일에 걸었어요.", "- 이번 주 합계: 1.9km")).isFalse();
        assertThat(InsightWeekdayGuard.allowed("세 번 걸었어요.", "- 이번 주 합계: 1.9km"))
                .as("요일을 안 말하면 근거가 없어도 통과다")
                .isTrue();
    }

    @Test
    @DisplayName("가드와 입력 글이 같은 것을 본다 — 진짜 render() 로 잰다")
    void readsTheRealRenderedInput() {
        WeeklyInsightInput input = new WeeklyInsightInput(
                LocalDate.of(2026, 9, 7), java.time.DayOfWeek.TUESDAY,
                1.9, 3, 2,
                List.of(0.0, 1.9, 0.0, 0.0, 0.0, 0.0, 0.0),
                List.of(0, 2, 0, 0, 0, 0, 0),
                0, 0, 0,
                List.of(new WalkStatsResponse.PartOfDayCount("dawn", 0, 0, 0),
                        new WalkStatsResponse.PartOfDayCount("morning", 0, 0, 0),
                        new WalkStatsResponse.PartOfDayCount("day", 3, 1.9, 2),
                        new WalkStatsResponse.PartOfDayCount("evening", 0, 0, 0)),
                "small", 36);
        String rendered = input.render();

        assertThat(InsightWeekdayGuard.walkedDaysIn(rendered))
                .as("직접 쓴 글이 아니라 진짜 입력에서 요일을 읽어야 한다 — 서식이 바뀌면 여기서 빨개진다")
                .containsExactly('화');
        assertThat(InsightWeekdayGuard.allowed("이번 주는 월·화에 걸었어요.", rendered)).isFalse();
        assertThat(InsightWeekdayGuard.allowed("이번 주는 화요일에 걸었어요.", rendered)).isTrue();
    }

    @Test
    @DisplayName("소수점 0.0 도 안 걸은 날이다")
    void zeroPointZeroIsNotAWalkedDay() {
        String input = "- 요일별 km: 월 0.0, 화 1.9, 수 0, 목 0, 금 0, 토 0, 일 0\n";

        assertThat(InsightWeekdayGuard.walkedDaysIn(input)).containsExactly('화');
    }
}
