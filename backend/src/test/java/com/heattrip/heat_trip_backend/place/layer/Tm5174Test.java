package com.heattrip.heat_trip_backend.place.layer;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 좌표계 변환을 <b>실제 장소</b>로 잰다 — 이슈 #291.
 *
 * <h2>정답은 어디서 왔나</h2>
 * <p>서울 열린데이터광장의 동물병원·동물판매업 샘플(등록 없이 5행을 주는 {@code sample} 키,
 * 2026-09-06)에서 TM 좌표와 도로명주소를 얻고, 같은 주소를 카카오 로컬 주소검색에 넣어 WGS84 를
 * 받았다. 인허가의 좌표는 건물 좌표이고 카카오는 도로명주소의 대표점이라 수십 m 는 다를 수 있다 —
 * 그래서 60m 를 허용한다. 변환이 틀리면(타원체·원점·보정) 수백 m 가 어긋난다.
 */
class Tm5174Test {

    /** {x, y, 카카오 lat, 카카오 lng}. */
    private static final List<double[]> TRUTH = List.of(
            // 늘서울피부과동물병원 — 서울 강남구 논현로 607
            new double[] {202875.328642756, 445077.204272347, 37.5079014141329, 127.033314058171},
            // 레오동물병원 — 서울 강서구 양천로 112
            new double[] {183708.951804407, 452336.611024956, 37.573162084683, 126.816357951274},
            // 준온누리약국 — 서울 강동구 올림픽로 783
            new double[] {211205.932552687, 449882.950636731, 37.5511436157073, 127.127611666932},
            // 도봉세명약국 — 서울 도봉구 방학로 176
            new double[] {202801.249503695, 462239.217329029, 37.6625112264806, 127.032541512918},
            // 기린온누리약국 — 서울 성북구 보국문로 33
            new double[] {200820.449805299, 456114.852392023, 37.6073770418433, 127.010124841427});

    private static final double TOLERANCE_M = 60;

    private final Tm5174 tm = new Tm5174();

    @Test
    @DisplayName("서울 다섯 곳이 카카오 주소 좌표와 60m 안에서 맞는다")
    void matchesKakaoWithinTolerance() {
        for (double[] row : TRUTH) {
            double[] got = tm.toLatLng(row[0], row[1]).orElseThrow();
            double error = haversine(got[0], got[1], row[2], row[3]);
            assertThat(error)
                    .as("x=%s y=%s → (%.6f, %.6f), 정답 (%.6f, %.6f)", row[0], row[1], got[0], got[1], row[2], row[3])
                    .isLessThan(TOLERANCE_M);
        }
    }

    @Test
    @DisplayName("타원체·원점을 틀리면 수백 m 가 어긋난다 — 허용치가 변환 오류를 가리지 못할 만큼 좁다")
    void toleranceIsTightEnoughToCatchAWrongDatum() {
        // 보정 없는 순수 평면 근사(원점에서 1° ≈ 111km)로 만든 값은 정답에서 멀어야 한다.
        double[] row = TRUTH.get(0);
        double naiveLat = 38 + (row[1] - 500_000) / 111_000.0;
        double naiveLng = 127.0028902777778 + (row[0] - 200_000) / (111_000.0 * Math.cos(Math.toRadians(38)));
        assertThat(haversine(naiveLat, naiveLng, row[2], row[3])).isGreaterThan(TOLERANCE_M * 3);
    }

    @Test
    @DisplayName("한국 밖으로 떨어지는 값은 버린다 — 다른 좌표계로 적힌 행이다")
    void rejectsCoordinatesOutsideKorea() {
        // 원점(0, 0)은 제주 서쪽 바다에 떨어져 상자 안이다 — "밖" 의 예로는 못 쓴다(실측). 서쪽으로 3,000km.
        assertThat(tm.toLatLng(-3_000_000, 0)).isEmpty();
        assertThat(tm.toLatLng(Double.NaN, 1)).isEmpty();
        assertThat(tm.toLatLng(9_000_000, 9_000_000)).isEmpty();
    }

    private static double haversine(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 6_371_000.0 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
