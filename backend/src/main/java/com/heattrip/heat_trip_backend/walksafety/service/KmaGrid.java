package com.heattrip.heat_trip_backend.walksafety.service;

/**
 * 기상청 5km 격자 ↔ 위경도. 기상청이 배포한 Lambert Conformal Conic 상수 그대로다.
 *
 * <p>앱은 격자 번호만 보내므로 서버가 위경도를 아는 일은 없다. 여기 역변환은 <b>격자 칸의
 * 중심</b>을 구해 가장 가까운 대기 측정소를 고르는 데만 쓴다 — 칸 하나가 5km 라 그 정도면 된다.
 *
 * <p>앱 쪽 순변환({@code kmaGrid()} in {@code walk_safety.dart})과 같은 상수라 서울시청
 * (37.5665, 126.9780) 은 (60, 127) 이고, 이 역변환은 그 칸의 중심을 돌려준다.
 */
public final class KmaGrid {
    /** 격자 번호의 유효 범위(기상청 격자 지도). */
    public static final int MAX_NX = 149;
    public static final int MAX_NY = 253;

    private static final double RE = 6371.00877;
    private static final double GRID = 5.0;
    private static final double SLAT1 = 30.0;
    private static final double SLAT2 = 60.0;
    private static final double OLON = 126.0;
    private static final double OLAT = 38.0;
    private static final double XO = 43.0;
    private static final double YO = 136.0;

    private KmaGrid() {
    }

    public static boolean isValid(int nx, int ny) {
        return nx >= 1 && nx <= MAX_NX && ny >= 1 && ny <= MAX_NY;
    }

    /** 격자 (nx, ny) 의 중심 위경도. */
    public static double[] toLatLng(int nx, int ny) {
        double degrad = Math.PI / 180.0;
        double raddeg = 180.0 / Math.PI;
        double re = RE / GRID;
        double slat1 = SLAT1 * degrad;
        double slat2 = SLAT2 * degrad;
        double olon = OLON * degrad;
        double olat = OLAT * degrad;

        double sn = Math.tan(Math.PI * 0.25 + slat2 * 0.5) / Math.tan(Math.PI * 0.25 + slat1 * 0.5);
        sn = Math.log(Math.cos(slat1) / Math.cos(slat2)) / Math.log(sn);
        double sf = Math.tan(Math.PI * 0.25 + slat1 * 0.5);
        sf = Math.pow(sf, sn) * Math.cos(slat1) / sn;
        double ro = Math.tan(Math.PI * 0.25 + olat * 0.5);
        ro = re * sf / Math.pow(ro, sn);

        double xn = nx - XO;
        double yn = ro - ny + YO;
        double ra = Math.sqrt(xn * xn + yn * yn);
        if (sn < 0.0) {
            ra = -ra;
        }
        double alat = Math.pow((re * sf / ra), (1.0 / sn));
        alat = 2.0 * Math.atan(alat) - Math.PI * 0.5;

        double theta;
        if (Math.abs(xn) <= 0.0) {
            theta = 0.0;
        } else if (Math.abs(yn) <= 0.0) {
            theta = Math.PI * 0.5;
            if (xn < 0.0) {
                theta = -theta;
            }
        } else {
            theta = Math.atan2(xn, yn);
        }
        double alon = theta / sn + olon;
        return new double[] {alat * raddeg, alon * raddeg};
    }

    /** 두 점 사이 거리(km). 측정소 고르기용이라 정밀도는 이 정도면 된다. */
    public static double haversineKm(double lat1, double lng1, double lat2, double lng2) {
        double r = 6371.0;
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 2 * r * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
