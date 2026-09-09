package com.heattrip.heat_trip_backend.walk.service;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 시간대를 나누는 경계 — 이슈 #359 1단계.
 *
 * <h2>왜 따로 재나</h2>
 * <p>통합 테스트는 "세 번 걸으면 한 칸에 셋이 모인다" 까지만 잰다 — 어느 칸인지는 테스트가
 * 도는 시각이 정한다. <b>경계</b>(05시와 06시가 다른 칸인가)는 그렇게 잴 수 없다.
 * 시각을 고정하려면 시계 빈을 갈아야 하고, 그러면 스프링 컨텍스트가 하나 더 뜬다(#21).
 *
 * <h2>새벽을 왜 따로 두나</h2>
 * <p>교대 근무나 더운 여름의 산책이 실제로 그 시간에 있다. 그것을 "저녁" 에 합치면
 * "저녁에 자주 나가시네요" 라는 <b>틀린 문장</b>이 사용자에게 나간다.
 *
 * <p>스프링을 안 띄운다(#21).
 */
class PartOfDayTest {

    @ParameterizedTest(name = "{0}시 → {1}")
    @CsvSource({
            // 새벽 — 자정부터 05시 59분까지
            "0, dawn",
            "3, dawn",
            "5, dawn",
            // 아침 — 06시부터
            "6, morning",
            "9, morning",
            "11, morning",
            // 낮 — 12시부터
            "12, afternoon",
            "15, afternoon",
            "17, afternoon",
            // 저녁 — 18시부터 자정 전까지
            "18, evening",
            "21, evening",
            "23, evening",
    })
    @DisplayName("경계가 06 · 12 · 18 시다")
    void bucketsByHour(int hour, String expected) {
        assertThat(WalkService.PARTS_OF_DAY.get(WalkService.partOfDayIndex(hour)))
                .isEqualTo(expected);
    }

    @Test
    @DisplayName("네 칸의 순서가 응답의 순서다 — 앱이 자리로 읽는다")
    void theOrderIsPartOfTheContract() {
        assertThat(WalkService.PARTS_OF_DAY)
                .containsExactly("dawn", "morning", "afternoon", "evening");
    }

    @Test
    @DisplayName("스물네 시간이 빠짐없이 한 칸씩 들어간다")
    void everyHourLandsSomewhere() {
        for (int hour = 0; hour < 24; hour++) {
            int index = WalkService.partOfDayIndex(hour);
            assertThat(index)
                    .as("%d시", hour)
                    .isBetween(0, WalkService.PARTS_OF_DAY.size() - 1);
        }
    }
}
