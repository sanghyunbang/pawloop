package com.heattrip.heat_trip_backend.place.service;

/**
 * 호출 예산을 나눠 갖는 세 자리 — 이슈 #40.
 *
 * <h2>왜 하나로 안 세는가</h2>
 * <p>상세 조회가 예산을 다 태우면 <b>지도가 함께 죽는다.</b> 둘은 사용자에게 다른 화면이고
 * 한쪽이 조여질 때 다른 쪽이 같이 조여질 이유가 없다.
 *
 * <p>{@code chat-poll} 과 {@code chat-send} 를 다른 버킷으로 둔 것과 같은 판단이다(#80).
 */
public enum KtoPool {

    /** {@code locationBasedList2} — 셀 하나의 스냅샷. 1건 = 1콜. */
    NEARBY("nearby"),

    /**
     * {@code areaBasedList2} — <b>전국 목록 한 벌</b>. 1페이지 = 1콜. 이슈 #273.
     *
     * <p><b>{@code NEARBY} 와 나누는 이유가 있다.</b> 카탈로그는 좌표를 <b>안 받는</b>
     * 길이고(A안 빌드가 쓴다), 셀 조회는 좌표를 받는 길이다. 한쪽이 예산을 다 태우면
     * 다른 쪽이 함께 죽는데, 그 둘은 <b>서로 다른 빌드가 쓰는 경로</b>라 같이 조여질
     * 이유가 없다.
     *
     * <p>한 번 데우는 데 드는 콜이 적다. 전국이 9,684곳이고 {@code numOfRows} 가
     * 1000 이라 <b>10콜</b>이면 한 벌이 다 온다(실측 2026-09-04).
     */
    CATALOG("catalog"),

    /**
     * {@code detailCommon2} + {@code detailPetTour2} — 장소 하나의 상세.
     *
     * <p><b>1건 = 2콜이다.</b> 예약할 때 2 단위를 잡는다 — 1 로 잡으면 150건이 통과해
     * 실제로는 300콜이 나가고 일 총량이 무너진다.
     */
    DETAIL("detail"),

    /**
     * 행정안전부 인허가(동물병원·동물판매업) — 이슈 #291. 1페이지 = 1콜. 같은 서비스키지만
     * 다른 API 라 한도도 따로다(개발계정 10,000/일).
     */
    LOCALDATA("localdata"),

    /** 두루누비 걷기여행길 코스 목록 — 이슈 #291. 1페이지 = 1콜(개발계정 1,000/일). GPX 파일은 안 센다. */
    DURUNUBI("durunubi"),
    /**
     * OpenRouteService 왕복 경로 — 이슈 #725. 시도 하나 = 1콜. 상대 한도가 하루 <b>200</b>이라
     * (실측 2026-09-20, 응답 헤더) 코스 하나에 seed 셋이면 하루 60여 코스다. 한 번 받은 코스는
     * {@code trail_route} 에 남아 다시 안 센다. KTO 가 아니지만 같은 표·같은 문을 쓴다 — 예산
     * 장치를 하나 더 만들 이유가 없다.
     */
    ORS_LOOP("ors-loop");

    private final String wireValue;

    KtoPool(String wireValue) {
        this.wireValue = wireValue;
    }

    /** {@code kto_call_budget.pool} 에 저장하는 문자열. 소문자다. */
    public String wireValue() {
        return wireValue;
    }
}
