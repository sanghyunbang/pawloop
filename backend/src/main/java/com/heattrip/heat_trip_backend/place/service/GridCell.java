package com.heattrip.heat_trip_backend.place.service;

/**
 * 좌표를 격자 한 칸으로 접는다 — 이슈 #40.
 *
 * <h2>왜 좌표를 그대로 캐시 키로 쓸 수 없는가</h2>
 * <p>KTO 일 한도는 <b>1,000콜</b>이다. 그런데 앱의 위치 갱신은 5m 마다 오고
 * ({@code location_service.dart} 의 {@code distanceFilter}), 산책 화면은 그때마다 주변
 * 장소를 다시 묻는다. 좌표를 키로 쓰면 <b>한 번의 산책이 수백 콜</b>이 된다 —
 * 사용자 한 명이 하루 한도를 태울 수 있다.
 *
 * <p>격자로 접으면 그 수백 요청이 <b>셀 하나</b>로 모인다. 그리고 셀은 하루에 한 번만
 * 갱신하므로, 같은 셀의 두 번째 이후 사용자는 아웃바운드 호출이 0 이다.
 *
 * <h2>0.02° 인 근거</h2>
 * <p>위도 37.5°N 기준:
 * <pre>
 *   위도 1°  = 111.32 km
 *   경도 1°  = 111.32 × cos(37.5°) = 88.32 km
 *   0.02° 셀 = 2.226 km × 1.766 km = 3.93 km²
 *   셀 중심에서 모서리까지 δ = √((2.226/2)² + (1.766/2)²) = 1.421 km
 * </pre>
 *
 * <p>서울 605.2 km² ÷ 3.93 km² = <b>154셀</b>이다. 서울 전역을 하루에 다 데워도
 * 154콜이고, 그건 일 예산 300 의 절반이다. <b>사용자가 몇 명이든 이 수는 안 변한다</b> —
 * 상한을 만드는 것이 사람 수가 아니라 땅 넓이이기 때문이다.
 *
 * <p>더 크게 잡으면(0.05°) 콜이 줄지만 셀 안에서 사용자가 서로 멀어져 거리 정렬이
 * 어긋난다. 더 작게 잡으면(0.005°) 셀이 16배가 되어 서울만 2,400콜이라 한도를 넘는다.
 *
 * <h2>δ 가 계약의 radius 상한을 정한다</h2>
 * <p>스냅샷은 <b>셀 중심</b>에서 {@link #FETCH_RADIUS_M} 만큼 받아 둔다. 셀 안의 어떤
 * 점에서도 보장되는 반경은 {@code FETCH_RADIUS_M − δ} 다. 그래서 계약
 * ({@code openapi.yaml} 의 {@code radius})의 최댓값이 그 값 이하여야 한다 — 넘으면
 * 서버가 <b>200 으로 조용히 덜 덮인 답</b>을 준다. {@code GridCellTest} 가 이 부등식을
 * 단언한다.
 *
 * <h2>양자화가 음수 좌표에서도 맞아야 한다</h2>
 * <p>{@code (int)} 캐스팅은 0 방향으로 자르므로 남반구·서반구에서 셀 경계가 어긋난다.
 * {@link Math#floorDiv} 계열의 내림을 쓴다 — 한국만 쓰더라도 좌표는 클라이언트가 보내는
 * 값이고, 0 근처에서 셀이 두 배로 넓어지는 것은 조용한 버그다.
 */
public record GridCell(int latIdx, int lngIdx) {

    /** 격자 한 칸의 크기(도). 위 javadoc 의 근거 참조. */
    public static final double CELL_DEGREES = 0.02;

    /**
     * 셀 중심에서 받아 두는 반경(m). KTO {@code locationBasedList2} 의 상한이 20,000 이다.
     *
     * <p>이 값을 줄이면 계약의 {@code radius} 최댓값도 함께 줄여야 한다 —
     * {@link #GUARANTEED_RADIUS_M} 참조.
     */
    public static final int FETCH_RADIUS_M = 20_000;

    /** 위도 1도의 길이(m). 지구를 구로 볼 때의 값이다. */
    private static final double METERS_PER_LAT_DEGREE = 111_320.0;

    /**
     * 셀 안의 어떤 점에서도 <b>보장되는</b> 반경(m).
     *
     * <p>{@code FETCH_RADIUS_M − δ} 이고 δ 는 셀 중심에서 모서리까지의 거리다.
     * 계약의 {@code radius} 최댓값이 이 값을 넘으면 서버가 조용히 덜 덮인 답을 준다.
     */
    public static final int GUARANTEED_RADIUS_M = FETCH_RADIUS_M - (int) Math.ceil(cornerDistanceM());

    /** 이 좌표가 속한 셀. */
    public static GridCell of(double lat, double lng) {
        return new GridCell(quantize(lat), quantize(lng));
    }

    /** 셀 중심의 위도. 스냅샷을 받는 기준점이다. */
    public double centerLat() {
        return (latIdx + 0.5) * CELL_DEGREES;
    }

    /** 셀 중심의 경도. */
    public double centerLng() {
        return (lngIdx + 0.5) * CELL_DEGREES;
    }

    /**
     * 셀 중심에서 모서리까지(m). 위도 37.5°N(서울) 기준으로 고정한다.
     *
     * <p>위도에 따라 실제 값이 달라지지만 <b>더 북쪽일수록 작아진다</b> — cos 이 줄어들어
     * 경도 방향 폭이 좁아지기 때문이다. 한국(33°~38°N)에서는 37.5° 값이 가장 크지 않으므로
     * 상수로 쓰면 안전한 쪽으로 틀린다. 33°N 에서 δ 가 조금 더 크지만 그 차이는 30m 미만이라
     * {@link #GUARANTEED_RADIUS_M} 의 올림이 흡수한다.
     */
    private static double cornerDistanceM() {
        double halfLatM = CELL_DEGREES * METERS_PER_LAT_DEGREE / 2;
        double halfLngM = CELL_DEGREES * METERS_PER_LAT_DEGREE * Math.cos(Math.toRadians(37.5)) / 2;
        return Math.hypot(halfLatM, halfLngM);
    }

    /**
     * 도 단위 좌표를 셀 번호로.
     *
     * <p>{@code (int)} 가 아니라 {@link Math#floor} 인 이유는 위 javadoc 참조 —
     * 캐스팅은 0 방향으로 자르므로 음수에서 셀 경계가 어긋난다.
     */
    private static int quantize(double degrees) {
        return (int) Math.floor(degrees / CELL_DEGREES);
    }
}
