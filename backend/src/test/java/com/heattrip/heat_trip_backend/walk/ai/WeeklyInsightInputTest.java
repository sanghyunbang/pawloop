package com.heattrip.heat_trip_backend.walk.ai;

import com.heattrip.heat_trip_backend.dog.DogProfileView;
import com.heattrip.heat_trip_backend.walk.dto.WalkStatsResponse;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** 모델에 주는 재료 — 이슈 #486. 숫자는 1단계 것만, 이름 · 좌표 · 장소는 없다. */
class WeeklyInsightInputTest {

    private static WalkStatsResponse stats() {
        return new WalkStatsResponse(
                LocalDate.of(2026, 9, 7), LocalDate.of(2026, 9, 13),
                List.of(1.2, 0.0, 2.0, 0.0, 0.0, 0.0, 0.0),
                List.of(18, 0, 30, 0, 0, 0, 0),
                3.2, 3, 1.07, 40.5, 20, 600,
                List.of(new WalkStatsResponse.TopPlace(
                        new WalkStatsResponse.PlaceRef("kto", "2733847", "서울숲"), 3)),
                new WalkStatsResponse.WeekSummary(2.0, 30, 1, List.of(
                        new WalkStatsResponse.PartOfDayCount("dawn", 0, 0, 0),
                        new WalkStatsResponse.PartOfDayCount("morning", 2, 3.2, 48),
                        new WalkStatsResponse.PartOfDayCount("afternoon", 0, 0, 0),
                        new WalkStatsResponse.PartOfDayCount("evening", 1, 0, 0))),
                null);
    }

    private static DogProfileView dog(String sizeKey, Integer ageMonths) {
        return new DogProfileView(sizeKey, ageMonths);
    }

    @Test
    @DisplayName("입력 글에는 1단계 숫자 · 요일 · 시간대 · 지난주 · 아이 크기와 나이대가 있다")
    void rendersTheFactsTheModelMayUse() {
        String text = WeeklyInsightInput.of(stats(), dog("small", 24), LocalDate.of(2026, 9, 9)).render();

        assertThat(text)
                .contains("오늘은 수요일")
                .contains("3.2km · 3회 · 48분")
                .contains("월 1.2, 화 0, 수 2")
                .contains("아침 2회")
                .contains("지난주: 2km · 1회 · 30분")
                .contains("소형견, 2살, 하루 권장 30분");
    }

    @Test
    @DisplayName("장소 · 좌표는 입력에 없다 — 이름은 아예 받지도 않는다(DogProfileView). 처리방침 v1.8 이 이 목록을 적는다")
    void leavesOutNamesPlacesAndCoordinates() {
        String text = WeeklyInsightInput.of(stats(), dog("small", 24), LocalDate.of(2026, 9, 9)).render();

        assertThat(text).doesNotContain("서울숲").doesNotContain("2733847")
                .doesNotContain("127.").doesNotContain("37.5");
        assertThat(DogProfileView.class.getRecordComponents()).extracting(c -> c.getName())
                .as("아이에 대해 받는 것은 크기와 나이대뿐")
                .containsExactly("sizeKey", "ageMonths");
    }

    @Test
    @DisplayName("아이가 없으면 아이 줄이 빠지고 권장 분도 없다")
    void worksWithoutADog() {
        WeeklyInsightInput input = WeeklyInsightInput.of(stats(), null, LocalDate.of(2026, 9, 9));

        assertThat(input.render()).doesNotContain("아이:");
        assertThat(input.recommendedMinutesPerDay()).isNull();
    }

    @Test
    @DisplayName("권장 분은 앱의 WalkGoal 과 같은 수 — 소형 30 · 중형 45 · 대형 60")
    void recommendedMinutesMatchTheApp() {
        assertThat(WeeklyInsightInput.of(stats(), dog("small", 24), LocalDate.of(2026, 9, 9)).recommendedMinutesPerDay()).isEqualTo(30);
        assertThat(WeeklyInsightInput.of(stats(), dog("medium", 24), LocalDate.of(2026, 9, 9)).recommendedMinutesPerDay()).isEqualTo(45);
        assertThat(WeeklyInsightInput.of(stats(), dog("large", 100), LocalDate.of(2026, 9, 9)).recommendedMinutesPerDay()).isEqualTo(60);
        assertThat(WeeklyInsightInput.of(stats(), dog("large", 100), LocalDate.of(2026, 9, 9)).render())
                .contains("시니어(8살)");
    }

    @Test
    @DisplayName("같은 입력은 같은 해시, 산책이 하나 늘면 다른 해시 — 캐시의 열쇠")
    void hashFollowsTheInput() {
        WeeklyInsightInput a = WeeklyInsightInput.of(stats(), dog("small", 24), LocalDate.of(2026, 9, 9));
        WeeklyInsightInput b = WeeklyInsightInput.of(stats(), dog("small", 24), LocalDate.of(2026, 9, 9));
        WeeklyInsightInput c = WeeklyInsightInput.of(stats().withAiSummary(null), dog("small", 25), LocalDate.of(2026, 9, 9));

        assertThat(a.hash()).isEqualTo(b.hash()).hasSize(64);
        assertThat(a.hash()).as("나이대가 같으면(2살) 해시도 같다").isEqualTo(c.hash());
        WeeklyInsightInput d = WeeklyInsightInput.of(stats(), dog("small", 24), LocalDate.of(2026, 9, 10));
        assertThat(a.hash()).as("요일이 바뀌면 문장도 바뀌어야 한다").isNotEqualTo(d.hash());
    }
}
