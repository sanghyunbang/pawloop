package com.heattrip.heat_trip_backend.walk.ai;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** 숫자 검사 — 이슈 #486. 모델이 숫자를 지어내면 문장을 통째로 버린다. */
class InsightNumberGuardTest {

    private static final String INPUT = """
            이번 주(월요일 9월 8일 시작, 오늘은 수요일)
            - 이번 주 합계: 3.2km · 3회 · 48분
            - 요일별 km: 월 1.2, 화 0, 수 2, 목 0, 금 0, 토 0, 일 0
            - 시간대별 횟수: 새벽 0회, 아침 2회, 낮 0회, 저녁 1회
            - 지난주: 2km · 1회 · 30분
            - 아이: 몸집 소형, 2살, 하루 권장 30분 안팎
            """;

    @Test
    @DisplayName("입력에 있는 숫자만 쓴 문장은 통과한다 — 단위나 조사는 보지 않는다")
    void passesWhenEveryNumberComesFromTheInput() {
        assertThat(InsightNumberGuard.allowed(
                "이번 주 3.2km 를 3번 걸었어요. 지난주 2km 보다 늘었네요.\n아침 산책 2회가 좋았어요.", INPUT))
                .isTrue();
    }

    @Test
    @DisplayName("입력에 없는 숫자가 하나라도 있으면 버린다 — 5km 를 지어낸 자리")
    void rejectsAnInventedNumber() {
        assertThat(InsightNumberGuard.allowed("이번 주 5km 를 걸었어요.", INPUT)).isFalse();
    }

    @Test
    @DisplayName("시각도 숫자다 — 입력에 시간대만 있고 '7시' 는 없으니 막힌다")
    void rejectsAClockTimeThatIsNotInTheInput() {
        assertThat(InsightNumberGuard.allowed("아침 7시에 나가 보세요.", INPUT)).isFalse();
    }

    @Test
    @DisplayName("3.0 과 3 은 같은 값이다 — 형식이 달라도 통과")
    void comparesByValueNotByFormat() {
        assertThat(InsightNumberGuard.allowed("3.0회 걸었어요", INPUT)).isTrue();
        assertThat(InsightNumberGuard.allowed("2.0km 였던 지난주", INPUT)).isTrue();
    }

    @Test
    @DisplayName("숫자가 없는 문장은 통과한다")
    void passesTextWithoutNumbers() {
        assertThat(InsightNumberGuard.allowed("이번 주도 꾸준했어요. 주말에 한 번 더 어떨까요?", INPUT)).isTrue();
    }

    @Test
    @DisplayName("천 단위 쉼표는 소수점이 아니다 — 1,200 은 1200")
    void readsThousandsSeparators() {
        assertThat(InsightNumberGuard.numbersIn("1,200m 와 3,2")).extracting(java.math.BigDecimal::toPlainString)
                .containsExactlyInAnyOrder("1200", "3.2");
    }
}
