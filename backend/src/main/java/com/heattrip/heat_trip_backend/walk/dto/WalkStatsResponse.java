package com.heattrip.heat_trip_backend.walk.dto;

import java.time.LocalDate;
import java.util.List;

/**
 * 계약의 {@code WalkStats} — 이슈 #145.
 *
 * <h2>두 기간이 한 응답에 있다</h2>
 * <p>화면이 둘 다 필요하다 — {@code me_screen} 은 "총 산책 / 총 거리 / <b>이번주</b>" 를 한
 * 카드에 나란히 놓고, {@code myrecords_screen} 은 전체 기간의 거리·횟수·시간을 센다.
 * 엔드포인트를 나누면 화면 하나가 두 번 부르고 요청 제한 항목도 하나 늘어난다.
 *
 * @param weekStart 이번 주 월요일(KST 날짜). {@code weekKm[0]} 이 이 날이다 — 응답이 스스로
 *                  기간을 말한다(#209 {@code Walks-medium-2}). 앱이 "서버가 이번 주를 줬겠지"
 *                  라고 가정하고 축 라벨을 그리지 않아도 된다
 * @param weekEnd   이번 주 일요일(KST 날짜, 포함). 항상 {@code weekStart + 6일}
 * @param weekKm    <b>월요일부터</b> 길이 7. 주 경계는 KST 다
 * @param weekMinutes 같은 요일 축의 <b>분</b>, 길이 7 (#341). 거리만으로는 목표를 말할 수
 *                  없다 — 권장 운동량이 "하루 30분" 처럼 <b>시간</b>으로 적혀 있어서다
 *                  (PDSA·Kennel Club). 초는 버리고 분만 준다: 목표가 분 단위라
 *                  초를 실어 보내면 화면이 매번 나눠야 하고, 그 나눗셈이 화면마다 다르면
 *                  같은 주에 다른 숫자가 나온다
 * @param walkCount 이번 주 산책 <b>건수</b>다. "산책한 날 수" 가 아니다 — 하루에 두 번
 *                  걸으면 2 다. 예전 더미 화면은 {@code weekKm} 에서 0 이 아닌 요일을 세어
 *                  날 수를 보여 줬다
 * @param topPlaces 자주 간 곳 상위 다섯, 전체 기간, {@code count} 내림차순 (#338).
 *                  <b>카탈로그에서 고른 곳만 센다</b> — 손으로 적은 이름은 계약의
 *                  {@link PlaceRef} 를 만들 수 없어(출처·id 가 없다) 여기 안 들어간다.
 *                  기록 카드에는 그 이름이 그대로 보인다
 */
public record WalkStatsResponse(
        LocalDate weekStart,
        LocalDate weekEnd,
        List<Double> weekKm,
        List<Integer> weekMinutes,
        double totalKm,
        int walkCount,
        double avgKm,
        double allTimeKm,
        int allTimeCount,
        int allTimeMinutes,
        List<TopPlace> topPlaces,

        /**
         * "이번 주 요약" 이 쓰는 계산 결과 — 이슈 #359 1단계. <b>문장은 앱이 만든다.</b>
         *
         * <p>여기 담는 것은 <b>앱이 스스로 못 구하는 것뿐</b>이다. 빠진 요일은 이미 있는
         * {@link #weekKm}·{@link #weekMinutes} 로 세면 되고, 달성률의 목표는 사용자가
         * 기기에서 고치는 값이라(#341) 서버가 모른다. 서버가 아는 것은 <b>전주 숫자</b>와
         * <b>시간대별 집계</b> 둘이다 — 둘 다 이번 주 응답만으로는 만들 수 없다.
         *
         * <p><b>문장을 서버가 만들지 않는 이유.</b> 문구는 화면의 것이고 자주 바뀐다.
         * 서버가 완성된 문장을 주면 문구 하나를 고치는 데 배포가 필요하고, 앱 버전마다
         * 다른 문장을 줘야 하는 날이 온다.
         */
        WeekSummary summary,
        AiSummary aiSummary) {

    /**
     * AI 주간 요약(#486) — 모델이 만든 두 문장 + 제안 한 줄. 키가 없거나 · 실패 · 상한 · 숫자 검사에서
     * 버렸으면 {@code null} 이고, 그때 앱은 카드도 라벨도 그리지 않는다.
     *
     * @param id       요약 행의 id — 앱이 👍/👎 를 {@code PUT /api/walks/insights/{id}/feedback} 로 보낼 때 쓴다
     * @param feedback 내가 남긴 평가 {@code up}·{@code down}, 안 눌렀으면 {@code null}. 문장이 다시 만들어지면 비워진다
     */
    public record AiSummary(long id, String text, java.time.Instant generatedAt, String feedback) {
    }

    public WalkStatsResponse withAiSummary(AiSummary ai) {
        return new WalkStatsResponse(weekStart, weekEnd, weekKm, weekMinutes, totalKm, walkCount, avgKm,
                allTimeKm, allTimeCount, allTimeMinutes, topPlaces, summary, ai);
    }

    /**
     * 계약의 {@code WalkStats.summary} — 이슈 #359.
     *
     * @param lastWeekKm      지난주 거리(km). 이번 주와 <b>같은 요일 기준</b>(KST 월~일)
     * @param lastWeekMinutes 지난주 분
     * @param lastWeekCount   지난주 산책 건수
     * @param byPartOfDay     시간대별 이번 주 집계. <b>항상 넷</b>이고 순서가 고정이다 —
     *                        {@code dawn}(00~05) · {@code morning}(06~11) ·
     *                        {@code afternoon}(12~17) · {@code evening}(18~23).
     *                        0 인 시간대도 뺀 게 아니라 0 으로 온다: 빠진 칸을 앱이
     *                        "없는 것" 과 "0인 것" 으로 갈라 다루지 않게 한다
     */
    public record WeekSummary(
            double lastWeekKm,
            int lastWeekMinutes,
            int lastWeekCount,
            List<PartOfDayCount> byPartOfDay) {
    }

    /** 시간대 한 칸. {@code part} 는 계약이 선언한 넷 중 하나다. */
    public record PartOfDayCount(String part, int count, double km, int minutes) {
    }

    /**
     * 계약의 {@code WalkStats.topPlaces[]}.
     *
     * <p>{@code place} 가 문자열이 아니라 {@link PlaceRef} 인 것은 #209 {@code Walks-low-1} 이
     * 고친 것이다 — 이름만 주면 {@code Place.contentId} 와 이어지지 않아 화면이 그 장소로
     * 갈 수 없다. 항상 빈 배열이던 그때가 모양을 바꾸는 데 비용이 0 인 유일한 시점이었고,
     * #338 이 그 모양 그대로 값을 채웠다.
     */
    public record TopPlace(PlaceRef place, int count) {
    }

    /** 계약의 {@code PlaceRef} — 장소의 식별자 셋. {@code source + contentId} 로 상세에 닿는다. */
    public record PlaceRef(String source, String contentId, String title) {
    }
}
