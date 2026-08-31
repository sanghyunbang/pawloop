package com.heattrip.heat_trip_backend.place.service;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 좌표 격자 — 이슈 #40.
 *
 * <p>여기가 지키는 것은 <b>"셀 안 어디서든 요청한 반경이 덮인다"</b> 하나다. 이 부등식이
 * 깨지면 서버가 200 으로 조용히 덜 덮인 답을 준다 — 사용자도 로그도 그것을 못 본다.
 */
class GridCellTest {

    /** 계약({@code openapi.yaml})의 {@code radius} 최댓값. 바뀌면 여기도 함께 바뀌어야 한다. */
    private static final int CONTRACT_MAX_RADIUS_M = 18_000;

    @Test
    @DisplayName("계약의 반경 상한이 셀 안에서 보장되는 반경 이하다 — 이게 깨지면 조용히 틀린 답이 나간다")
    void theContractMaximumFitsInsideWhatWeGuarantee() {
        assertThat(CONTRACT_MAX_RADIUS_M)
                .as("""
                        스냅샷은 셀 중심에서 %dm 를 받아 둔다. 셀 안의 어떤 점에서도 보장되는
                        반경은 거기서 셀 반지름 δ 를 뺀 %dm 다.

                        계약이 그보다 큰 값을 허용하면, 그 요청은 바깥 테두리가 덜 덮인 답을
                        200 으로 받는다. 오류도 로그도 없다.
                        """.formatted(GridCell.FETCH_RADIUS_M, GridCell.GUARANTEED_RADIUS_M))
                .isLessThanOrEqualTo(GridCell.GUARANTEED_RADIUS_M);
    }

    @Test
    @DisplayName("셀 중심에서 모서리까지가 1.4km 남짓이다 — 0.02° 근거의 산수")
    void theCellIsAboutWhatTheJavadocClaims() {
        int delta = GridCell.FETCH_RADIUS_M - GridCell.GUARANTEED_RADIUS_M;

        assertThat(delta)
                .as("javadoc 이 δ ≈ 1,421m 라고 적었다. 계산이 그것과 다르면 근거가 낡은 것이다")
                .isBetween(1_400, 1_450);
    }

    @Test
    @DisplayName("같은 셀 안의 두 점은 같은 셀로 접힌다 — 그게 격자의 존재 이유다")
    void nearbyPointsFoldIntoOneCell() {
        // 126.98 은 셀 경계다(126.98 / 0.02 = 6349.0). 경계를 안 걸치게 고른다 —
        // 처음에 126.9800 을 썼다가 빨간불을 봤고, 틀린 것은 코드가 아니라 이 좌표였다.
        GridCell a = GridCell.of(37.5665, 126.9780);
        GridCell b = GridCell.of(37.5700, 126.9795);

        assertThat(b)
                .as("""
                        앱은 5m 마다 위치를 갱신한다. 좌표를 그대로 키로 쓰면 한 번의 산책이
                        수백 콜이 되고, 사용자 한 명이 하루 한도(1,000)를 태울 수 있다.
                        """)
                .isEqualTo(a);
    }

    @Test
    @DisplayName("경계를 넘으면 다른 셀이다 — 0.02 의 배수가 다음 셀의 시작이다")
    void theBoundaryBelongsToTheNextCell() {
        // 126.98 / 0.02 = 6349.0 이므로 126.98 은 6349 셀의 첫 점이다.
        assertThat(GridCell.of(37.5, 126.9799).lngIdx()).isEqualTo(6348);
        assertThat(GridCell.of(37.5, 126.9800).lngIdx()).isEqualTo(6349);
    }

    @Test
    @DisplayName("멀리 떨어진 점은 다른 셀이다")
    void distantPointsAreDifferentCells() {
        assertThat(GridCell.of(37.5665, 126.9780))
                .isNotEqualTo(GridCell.of(35.1796, 129.0756));
    }

    @Test
    @DisplayName("셀 중심이 그 셀 안에 있다 — 스냅샷을 받는 기준점이라 어긋나면 안 된다")
    void theCenterBelongsToItsOwnCell() {
        GridCell cell = GridCell.of(37.5665, 126.9780);

        assertThat(GridCell.of(cell.centerLat(), cell.centerLng())).isEqualTo(cell);
    }

    @Test
    @DisplayName("음수 좌표에서도 셀 경계가 어긋나지 않는다 — (int) 캐스팅의 함정")
    void negativeCoordinatesFoldCorrectly() {
        // (int) 는 0 방향으로 자른다. -0.01 과 0.01 이 같은 셀이 되면 0 근처에서 셀이
        // 두 배로 넓어지고, 그건 조용한 버그다. 한국만 쓰더라도 좌표는 클라이언트가 보낸다.
        assertThat(GridCell.of(-0.01, -0.01))
                .isNotEqualTo(GridCell.of(0.01, 0.01));

        assertThat(GridCell.of(-0.01, 0.0).latIdx()).isEqualTo(-1);
    }

    @Test
    @DisplayName("서울을 덮는 셀 수가 예산 안에 들어온다 — 이 수가 하루 상한의 근거다")
    void seoulFitsInsideTheDailyBudget() {
        // 서울 면적 605.2 km². 셀 하나는 0.02° × 0.02° 다.
        double cellAreaKm2 = (GridCell.CELL_DEGREES * 111.32)
                * (GridCell.CELL_DEGREES * 111.32 * Math.cos(Math.toRadians(37.5)));
        int cells = (int) Math.ceil(605.2 / cellAreaKm2);

        assertThat(cells)
                .as("""
                        KtoBudgetProperties 가 nearby 상한을 300 으로 잡은 근거가 이 수다.
                        서울 전역을 하루에 다 데워도 상한의 절반이고, **사용자가 몇 명이든
                        이 수는 안 변한다** — 상한을 만드는 것이 사람 수가 아니라 땅 넓이다.
                        """)
                .isLessThan(300);
    }
}
