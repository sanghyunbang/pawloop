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
 * @param walkCount 이번 주 산책 <b>건수</b>다. "산책한 날 수" 가 아니다 — 하루에 두 번
 *                  걸으면 2 다. 예전 더미 화면은 {@code weekKm} 에서 0 이 아닌 요일을 세어
 *                  날 수를 보여 줬다
 * @param topPlaces <b>지금은 항상 빈 배열이다.</b> {@code walk} 에 장소 축이 없어 셀 근거가
 *                  없다. 그럴듯한 값을 만들어 넣으면 화면이 거짓말을 한다
 */
public record WalkStatsResponse(
        LocalDate weekStart,
        LocalDate weekEnd,
        List<Double> weekKm,
        double totalKm,
        int walkCount,
        double avgKm,
        double allTimeKm,
        int allTimeCount,
        int allTimeMinutes,
        List<TopPlace> topPlaces) {

    /**
     * 계약의 {@code WalkStats.topPlaces[]}. 채워지는 날까지 이 record 는 쓰이지 않는다.
     *
     * <p>{@code place} 가 문자열이 아니라 {@link PlaceRef} 인 것은 #209 {@code Walks-low-1} 이
     * 고친 것이다 — 이름만 주면 {@code Place.contentId} 와 이어지지 않아 화면이 그 장소로
     * 갈 수 없다. 항상 빈 배열인 지금이 모양을 바꾸는 데 비용이 0 인 유일한 시점이었다.
     */
    public record TopPlace(PlaceRef place, int count) {
    }

    /** 계약의 {@code PlaceRef} — 장소의 식별자 셋. {@code source + contentId} 로 상세에 닿는다. */
    public record PlaceRef(String source, String contentId, String title) {
    }
}
