package com.heattrip.heat_trip_backend.walk.dto;

import java.util.List;

/**
 * 계약의 {@code WalkStats} — 이슈 #145.
 *
 * <h2>두 기간이 한 응답에 있다</h2>
 * <p>화면이 둘 다 필요하다 — {@code me_screen} 은 "총 산책 / 총 거리 / <b>이번주</b>" 를 한
 * 카드에 나란히 놓고, {@code myrecords_screen} 은 전체 기간의 거리·횟수·시간을 센다.
 * 엔드포인트를 나누면 화면 하나가 두 번 부르고 요청 제한 항목도 하나 늘어난다.
 *
 * @param weekKm    <b>월요일부터</b> 길이 7. 주 경계는 KST 다
 * @param walkCount 이번 주 산책 <b>건수</b>다. "산책한 날 수" 가 아니다 — 하루에 두 번
 *                  걸으면 2 다. 예전 더미 화면은 {@code weekKm} 에서 0 이 아닌 요일을 세어
 *                  날 수를 보여 줬다
 * @param topPlaces <b>지금은 항상 빈 배열이다.</b> {@code walk} 에 장소 축이 없어 셀 근거가
 *                  없다. 그럴듯한 값을 만들어 넣으면 화면이 거짓말을 한다
 */
public record WalkStatsResponse(
        List<Double> weekKm,
        double totalKm,
        int walkCount,
        double avgKm,
        double allTimeKm,
        int allTimeCount,
        int allTimeMinutes,
        List<TopPlace> topPlaces) {

    /** 계약의 {@code WalkStats.topPlaces[]}. 채워지는 날까지 이 record 는 쓰이지 않는다. */
    public record TopPlace(String place, int count) {
    }
}
