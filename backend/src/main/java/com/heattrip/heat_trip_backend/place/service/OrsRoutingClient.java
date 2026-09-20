package com.heattrip.heat_trip_backend.place.service;

import java.util.List;
import java.util.Optional;

/**
 * 왕복 산책 경로를 만드는 바깥 길찾기 — 이슈 #725. 지금 구현은 OpenRouteService 하나다.
 *
 * <p>인터페이스로 둔 이유: 통합 검사가 진짜 ORS 를 부르지 않고(한도가 하루 200) 가짜를 꽂는다.
 * 나중에 GraphHopper 를 직접 띄우면 이 자리만 바뀐다.
 */
public interface OrsRoutingClient {

    /**
     * 경로 하나.
     *
     * @param distanceM 실제 길이(m) — 부탁한 길이가 아니라 나온 길이다
     * @param durationS 도보 예상 시간(초)
     * @param lngLat    {@code [경도, 위도]} 점들. 처음과 끝이 같은 자리다(왕복)
     */
    record Loop(double distanceM, double durationS, List<double[]> lngLat) {
    }

    /** 키가 있어 부를 수 있는가. 없으면 기능이 꺼진다 — 호출부가 먼저 묻는다. */
    boolean isConfigured();

    /**
     * 이 자리에서 출발해 이 자리로 돌아오는 도보 경로 하나.
     *
     * @param lengthM 부탁하는 길이(m). 결과는 어긋날 수 있다 — 고르는 것은 {@link LoopPicker}
     * @param points  왕복을 만들 때 찍는 경유점 수
     * @param seed    같은 자리·길이에서 다른 모양을 얻는 씨앗
     * @return 못 받으면 빈 값(거절 · 시간 초과 · 이상한 본문). 던지지 않는다
     */
    Optional<Loop> roundTrip(double lat, double lng, int lengthM, int points, int seed);
}
