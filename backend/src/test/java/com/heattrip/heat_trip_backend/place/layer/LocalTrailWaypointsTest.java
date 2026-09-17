package com.heattrip.heat_trip_backend.place.layer;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 동네 길의 경유지 글을 자르는 규칙 — 이슈 #619. 스프링 없이 순수 함수만 본다.
 *
 * <p>여기 값들은 지어낸 것이 아니라 <b>자산에 실제로 있는 글</b>이다. 전수로 잰 결과는
 * {@link LocalTrailAssetRouteTest} 가 자산 전체를 돌면서 다시 확인한다.
 */
class LocalTrailWaypointsTest {

    @Test
    @DisplayName("화살표로 자른다 — 가장 흔한 모양(1,302개 중 1,008개)")
    void splitsOnArrows() {
        assertThat(LocalTrailWaypoints.split("보신각 → 보성사 터 → 탑골공원"))
                .containsExactly("보신각", "보성사 터", "탑골공원");
    }

    @Test
    @DisplayName("화살표가 있으면 붙임표는 이름의 일부다 — K-55 를 쪼개지 않는다")
    void keepsHyphenInsideNamesWhenArrowsDecideTheSplit() {
        assertThat(LocalTrailWaypoints.split("진위역 → K-55 → 신장쇼핑몰 → 서정리역"))
                .containsExactly("진위역", "K-55", "신장쇼핑몰", "서정리역");
    }

    @Test
    @DisplayName("붙임표뿐이면 그것이 구분자다 — 한 덩어리로 남기지 않는다")
    void splitsOnHyphenWhenItIsTheOnlySeparator() {
        assertThat(LocalTrailWaypoints.split("속초등대전망대-영금정쉼터-등대해수욕장-장사항"))
                .containsExactly("속초등대전망대", "영금정쉼터", "등대해수욕장", "장사항");
    }

    @Test
    @DisplayName("괄호 안의 구분자로는 자르지 않는다 — 짝이 깨진 반쪽 이름을 만들지 않는다")
    void neverSplitsInsideParentheses() {
        assertThat(LocalTrailWaypoints.split("둘레길(연화산유원지~송이재입구~연화산유원지)"))
                .containsExactly("둘레길(연화산유원지~송이재입구~연화산유원지)");

        assertThat(LocalTrailWaypoints.split(
                "석파령→덕두원(명월길)→수레너미(덕두원2리, 1905번 버스정류장 앞)→방동1리 마을회관"))
                .containsExactly("석파령", "덕두원(명월길)",
                        "수레너미(덕두원2리, 1905번 버스정류장 앞)", "방동1리 마을회관");
    }

    @Test
    @DisplayName("괄호 밖에 화살표가 있으면 괄호 안의 붙임표는 안 본다")
    void parenthesisContentsDoNotVoteOnTheSeparator() {
        // 괄호 안에만 ~ 가 있는 글이다. 그것이 "강한 구분자가 있다" 로 세어지면
        // 괄호 밖의 - 가 구분자에서 빠져 통째로 한 조각이 된다.
        assertThat(LocalTrailWaypoints.split("가평역(자라섬~남이섬)-달전리-상천역"))
                .containsExactly("가평역(자라섬~남이섬)", "달전리", "상천역");
    }

    @Test
    @DisplayName("긴 구분자를 먼저 본다 — -> 가 - 로 갈려 빈 조각을 남기지 않는다")
    void longerSeparatorsWinOverTheirPrefixes() {
        assertThat(LocalTrailWaypoints.split("대명항->덕포진->쇄암리 쉼터"))
                .containsExactly("대명항", "덕포진", "쇄암리 쉼터");
    }

    @Test
    @DisplayName("자를 것이 없으면 통째로 한 조각 — 1,302개 중 20개가 이렇다")
    void keepsUnsplittableTextAsOnePiece() {
        assertThat(LocalTrailWaypoints.split("영랑호 둘레를 한 바퀴 도는 길"))
                .containsExactly("영랑호 둘레를 한 바퀴 도는 길");
    }

    @Test
    @DisplayName("글이 없으면 빈 목록 — 조각 0개를 주면 '아무 데도 안 간다' 가 된다")
    void emptyTextGivesNoStops() {
        assertThat(LocalTrailWaypoints.split(null)).isEmpty();
        assertThat(LocalTrailWaypoints.split("")).isEmpty();
        assertThat(LocalTrailWaypoints.split("   ")).isEmpty();
        assertThat(LocalTrailWaypoints.split("→ → →")).isEmpty();
    }

    @Test
    @DisplayName("조각 수에 울타리가 있다 — 깨진 글이 화면을 끝없이 밀지 않는다")
    void capsTheNumberOfStops() {
        StringBuilder many = new StringBuilder("곳0");
        for (int i = 1; i < LocalTrailWaypoints.MAX_STOPS + 30; i++) {
            many.append("→곳").append(i);
        }
        List<String> stops = LocalTrailWaypoints.split(many.toString());
        assertThat(stops).hasSize(LocalTrailWaypoints.MAX_STOPS);
        assertThat(stops.get(0)).isEqualTo("곳0");
    }
}
