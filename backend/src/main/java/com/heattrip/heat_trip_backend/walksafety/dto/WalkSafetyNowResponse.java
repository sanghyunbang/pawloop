package com.heattrip.heat_trip_backend.walksafety.dto;

import java.time.Instant;

/**
 * {@code GET /api/walk-safety/now} 의 응답 — 관측값 한 묶음. 판정은 앱이 한다.
 *
 * @param tempC       기온(°C). 기상청 초단기실황 {@code T1H}. 이 값이 없으면 응답 자체가 없다(503)
 * @param humidity    습도(%). {@code REH}. 없으면 {@code null}
 * @param rain1hMm    1시간 강수량(mm). {@code RN1}. 없으면 {@code null}
 * @param precipType  강수형태. {@code PTY} — 0 없음 · 1 비 · 2 비/눈 · 3 눈 · 5 빗방울 · 6 빗방울눈날림 · 7 눈날림
 * @param pm10        미세먼지(㎍/㎥). 에어코리아가 안 붙어 있으면 {@code null}
 * @param pm25        초미세먼지(㎍/㎥). 같다
 * @param station     미세먼지 측정소 이름(격자 중심에서 가장 가까운 곳). PM 이 없으면 {@code null}
 * @param observedAt  서버가 이 묶음을 만든 시각(UTC)
 */
public record WalkSafetyNowResponse(
        double tempC,
        Integer humidity,
        Double rain1hMm,
        Integer precipType,
        Integer pm10,
        Integer pm25,
        String station,
        Instant observedAt) {
}
