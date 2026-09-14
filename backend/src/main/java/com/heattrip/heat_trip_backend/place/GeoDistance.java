package com.heattrip.heat_trip_backend.place;

/**
 * 두 좌표 사이의 거리(m) — 하버사인.
 *
 * <p>주변 조회(반경 · 거리순)와 겹침 정리(#411)가 <b>같은 자</b>를 쓴다. 자가 둘이면 "200m 안" 이
 * 조회와 정리에서 다른 200m 가 된다.
 */
public final class GeoDistance {

    private static final double EARTH_RADIUS_M = 6_371_000.0;

    private GeoDistance() {
    }

    public static double metersBetween(double lat1, double lng1, double lat2, double lng2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    }
}
