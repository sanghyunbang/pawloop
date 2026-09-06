package com.heattrip.heat_trip_backend.place.layer;

import org.locationtech.proj4j.CRSFactory;
import org.locationtech.proj4j.CoordinateReferenceSystem;
import org.locationtech.proj4j.CoordinateTransform;
import org.locationtech.proj4j.CoordinateTransformFactory;
import org.locationtech.proj4j.ProjCoordinate;
import org.springframework.stereotype.Component;

import java.util.Optional;

/**
 * 인허가 데이터의 좌표계(EPSG:5174, Bessel 중부원점 TM)를 WGS84 경위도로 — 이슈 #291.
 *
 * <h2>왜 변환이 필요한가</h2>
 * <p>행정안전부 인허가 데이터의 {@code CRD_INFO_X}/{@code CRD_INFO_Y} 는 경위도가 아니라
 * <b>미터 단위 평면 좌표</b>다(원점 북위 38°·동경 127°00′10.405″, 가원점 200,000/500,000).
 * 그대로 지도에 찍으면 한반도 밖에 찍힌다. 데이터 설명이 "보정계수 안들어간 Bessel
 * 중부원점TM(EPSG:5174)" 라고 적시하고 있다.
 *
 * <h2>왜 proj4j 인가</h2>
 * <p>횡축 메르카토르 역변환에 Bessel→WGS84 7-파라미터 데이텀 변환이 겹친다. 손으로 쓰면
 * 수백 m 가 조용히 어긋나도 아무도 모른다 — 서울 다섯 곳의 카카오 주소 좌표와 견주는
 * 테스트가 이 클래스를 잠근다({@code Tm5174Test}).
 *
 * <h2>스레드</h2>
 * <p>proj4j 의 변환 객체는 내부 작업 좌표를 재사용해 <b>스레드 안전하지 않다.</b> 적재는
 * 한 스레드지만, 그 사실에 기대지 않고 {@code synchronized} 로 잠근다.
 */
@Component
public class Tm5174 {

    /**
     * EPSG:5174 — Korean 1985 / Modified Central Belt.
     *
     * <p>{@code lon_0} 이 127° 가 아니라 127°00′10.405″ 인 것이 "Modified" 다. 127° 로 두면
     * 동서로 약 250m 가 어긋난다. {@code towgs84} 는 Bessel 타원체를 WGS84 로 옮기는
     * 7-파라미터로, EPSG 등록 값 그대로다.
     */
    static final String PROJ4_5174 = "+proj=tmerc +lat_0=38 +lon_0=127.0028902777778 +k=1"
            + " +x_0=200000 +y_0=500000 +ellps=bessel +units=m +no_defs"
            + " +towgs84=-115.80,474.99,674.11,1.16,-2.31,-1.63,6.43";

    private static final String PROJ4_WGS84 = "+proj=longlat +datum=WGS84 +no_defs";

    /** 이 밖의 결과는 좌표가 애초에 다른 체계였다는 뜻이다 — 버린다. */
    private static final double MIN_LAT = 32.0;
    private static final double MAX_LAT = 39.5;
    private static final double MIN_LNG = 124.0;
    private static final double MAX_LNG = 132.5;

    private final CoordinateTransform toWgs84;

    public Tm5174() {
        CRSFactory factory = new CRSFactory();
        CoordinateReferenceSystem source = factory.createFromParameters("EPSG:5174", PROJ4_5174);
        CoordinateReferenceSystem target = factory.createFromParameters("EPSG:4326", PROJ4_WGS84);
        this.toWgs84 = new CoordinateTransformFactory().createTransform(source, target);
    }

    /**
     * @return {@code [lat, lng]}. 좌표가 한국 밖으로 떨어지면 비어 있다
     */
    public synchronized Optional<double[]> toLatLng(double x, double y) {
        if (Double.isNaN(x) || Double.isNaN(y) || Double.isInfinite(x) || Double.isInfinite(y)) {
            return Optional.empty();
        }
        ProjCoordinate out = new ProjCoordinate();
        try {
            toWgs84.transform(new ProjCoordinate(x, y), out);
        } catch (RuntimeException e) {
            // 터무니없는 값(수천 km 밖)이면 proj4j 가 "Latitude is out of range" 로 던진다 — 실측.
            // 그 행은 다른 좌표계로 적힌 것이다. 버린다.
            return Optional.empty();
        }
        double lng = out.x;
        double lat = out.y;
        if (lat < MIN_LAT || lat > MAX_LAT || lng < MIN_LNG || lng > MAX_LNG) {
            return Optional.empty();
        }
        return Optional.of(new double[] {lat, lng});
    }
}
