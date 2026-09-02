package com.heattrip.heat_trip_backend.walk.service;

import org.locationtech.jts.geom.Coordinate;
import org.locationtech.jts.geom.GeometryFactory;
import org.locationtech.jts.geom.LineString;
import org.locationtech.jts.geom.PrecisionModel;

import java.util.ArrayList;
import java.util.List;

/**
 * 좌표 배열 ↔ {@link LineString} — 이슈 #145.
 *
 * <h2>순서가 이 파일의 전부다</h2>
 * <p>계약도 JTS 도 <b>{@code [경도, 위도]}</b> 다. 사람이 말하는 "위도, 경도" 와 <b>반대</b>이고,
 * 앱은 {@code NLatLng(latitude, longitude)} 로 <b>(위도, 경도)</b> 순서로 들고 있다. 즉 옮기는
 * 자리에서 한 번 뒤집어야 하고, 뒤집는 것을 잊으면 <b>지도에 엉뚱한 곳이 찍힌다.</b>
 * #24 가 이것을 M1 의 위험으로 미리 적어 뒀다.
 *
 * <p>그래서 이 클래스는 <b>순서를 이름으로 못 박는다</b> — {@code lng} 가 먼저다.
 *
 * <h2>뒤집힌 것을 서버가 잡는다 — 다만 그물이지 보증이 아니다</h2>
 * <p>위도는 ±90 을 넘을 수 없다. 그래서 <b>둘째 값의 절댓값이 90 을 넘으면</b> 그 쌍은
 * 위도일 수 없고, 뒤집혀 온 것이다. 한국 좌표({@code lng≈127}, {@code lat≈37})는 뒤집히면
 * 둘째가 127 이 되므로 <b>100% 걸린다.</b>
 *
 * <p><b>적도 근처는 안 걸린다.</b> 두 값이 모두 90 미만이면 어느 쪽이 위도인지 숫자만 보고는
 * 알 수 없다. 이 검사는 흔한 실수를 싸게 잡는 그물이지 정확성의 보증이 아니다.
 */
public final class WalkPath {

    /** WGS84. 계약과 컬럼({@code linestring srid 4326})이 정한 값이다. */
    public static final int SRID = 4326;

    /**
     * 경로 점 수 상한.
     *
     * <p>20,000 은 <b>관측이 아니다.</b> 1초에 한 점이면 5시간 반이고, 5m 마다 한 점이면
     * 100km 다 — 하루 산책의 바깥 경계로 잡은 값이다. 상한이 없으면 요청 하나가 임의 크기의
     * 행을 만들 수 있다.
     */
    public static final int MAX_POINTS = 20_000;

    private static final GeometryFactory FACTORY =
            new GeometryFactory(new PrecisionModel(), SRID);

    private WalkPath() {
    }

    /**
     * 계약의 {@code path}({@code [[경도, 위도], ...]})를 선으로 옮긴다.
     *
     * @return 점이 2개 미만이면 {@code null} — <b>LINESTRING 은 점 하나로 만들 수 없다.</b>
     *         시작점을 두 번 넣어 길이 0 짜리 선을 만들지 않는다(지도에 점이 찍힌다).
     * @throws IllegalArgumentException 모양이 계약과 다르거나, 값이 좌표 범위를 벗어나거나,
     *                                  뒤집혀 보인 경우. 400 이 된다
     */
    /**
     * 점별 시각을 JSON 배열 문자열로 만든다 — 이슈 #155.
     *
     * <p><b>{@code path} 와 길이가 같아야 한다.</b> 짝이 안 맞으면 어느 점이 언제인지
     * 말해 주지 못하므로 저장할 가치가 없다. DB 에 CHECK 를 걸지 않았으므로
     * <b>이 검사가 유일한 방어선</b>이다(13_walk_path_t.sql §B-1).
     *
     * <p>경로가 없으면 시각도 없어야 한다 — 경로 없는 시각은 뜻이 없다.
     *
     * @param points 경로. {@code null} 이거나 비어 있을 수 있다
     * @param seconds 시작 기준 델타 초. {@code null} 이면 저장하지 않는다
     * @return JSON 배열 문자열. 실을 것이 없으면 {@code null}
     * @throws IllegalArgumentException 길이가 다르거나, 경로 없이 시각만 왔거나,
     *         초가 음수이거나 뒤로 흐를 때
     */
    public static String toPathTimes(List<List<Double>> points, List<Integer> seconds) {
        if (seconds == null || seconds.isEmpty()) return null;

        int pointCount = points == null ? 0 : points.size();
        if (pointCount == 0) {
            throw new IllegalArgumentException(
                    "경로 없이 점별 시각만 보낼 수 없습니다.");
        }
        if (seconds.size() != pointCount) {
            throw new IllegalArgumentException(
                    "점별 시각의 개수가 경로의 점 개수와 다릅니다.");
        }

        // 음수는 시작 전이고, 뒤로 흐르는 것은 시계가 거꾸로 간 것이다. 둘 다 그 배열로
        // 할 수 있는 계산(구간 페이스)이 의미를 잃는다. 조용히 받아 두면 그 계산을
        // 처음 하는 날까지 아무도 모른다.
        int previous = -1;
        StringBuilder json = new StringBuilder(seconds.size() * 4 + 2).append('[');
        for (int i = 0; i < seconds.size(); i++) {
            Integer value = seconds.get(i);
            if (value == null) {
                throw new IllegalArgumentException("점별 시각에 빈 값이 있습니다.");
            }
            if (value < 0) {
                throw new IllegalArgumentException("점별 시각은 음수일 수 없습니다.");
            }
            if (value < previous) {
                throw new IllegalArgumentException("점별 시각이 뒤로 흐릅니다.");
            }
            previous = value;
            if (i > 0) json.append(',');
            json.append(value.intValue());
        }
        return json.append(']').toString();
    }

    public static LineString toLineString(List<List<Double>> points) {
        if (points == null || points.size() < 2) {
            return null;
        }
        if (points.size() > MAX_POINTS) {
            throw new IllegalArgumentException(
                    "경로 점은 " + MAX_POINTS + "개를 넘을 수 없습니다.");
        }

        List<Coordinate> coordinates = new ArrayList<>(points.size());
        for (List<Double> point : points) {
            coordinates.add(coordinateOf(point));
        }
        return FACTORY.createLineString(coordinates.toArray(Coordinate[]::new));
    }

    /** 선을 계약의 {@code [[경도, 위도], ...]} 로 되돌린다. {@code null} 은 {@code null} 이다. */
    public static List<List<Double>> toPoints(LineString path) {
        if (path == null) {
            return null;
        }
        List<List<Double>> points = new ArrayList<>(path.getNumPoints());
        for (int i = 0; i < path.getNumPoints(); i++) {
            Coordinate coordinate = path.getCoordinateN(i);
            points.add(List.of(coordinate.x, coordinate.y));
        }
        return points;
    }

    /** {@code [경도, 위도]} 한 쌍. JTS 는 {@code (x, y)} 라 <b>경도가 x</b> 다. */
    private static Coordinate coordinateOf(List<Double> point) {
        if (point == null || point.size() != 2
                || point.get(0) == null || point.get(1) == null) {
            throw new IllegalArgumentException("경로의 각 점은 [경도, 위도] 두 값이어야 합니다.");
        }
        double lng = point.get(0);
        double lat = point.get(1);

        if (!Double.isFinite(lng) || !Double.isFinite(lat)) {
            throw new IllegalArgumentException("경로에 숫자가 아닌 좌표가 있습니다.");
        }
        if (Math.abs(lat) > 90) {
            // 위도가 ±90 을 넘을 수 없다 — 뒤집혀 온 것이다. 클래스 javadoc 참조.
            throw new IllegalArgumentException(
                    "경로의 좌표 순서가 [경도, 위도] 가 아닙니다. 위도는 ±90 을 넘을 수 없습니다.");
        }
        if (Math.abs(lng) > 180) {
            throw new IllegalArgumentException("경도는 ±180 을 넘을 수 없습니다.");
        }
        return new Coordinate(lng, lat);
    }
}
