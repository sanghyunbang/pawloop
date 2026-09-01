package com.heattrip.heat_trip_backend.walk;

import com.heattrip.heat_trip_backend.walk.service.WalkPath;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.locationtech.jts.geom.LineString;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 좌표 순서 — 이슈 #145 완료 조건 3.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 여기서 보는 것은 순수한 변환이고, 컨테이너를 띄우면
 * 같은 것을 30초 느리게 확인하게 된다.
 *
 * <p><b>#24 가 이 자리를 미리 짚었다</b> — "GPS 경로를 서버에 보내기 시작하는 순간 이
 * 모호함이 실제 버그가 된다."
 */
class WalkPathTest {

    @Test
    @DisplayName("[경도, 위도] 로 들어와 [경도, 위도] 로 나간다 — JTS 의 x 가 경도다")
    void keepsLongitudeFirst() {
        List<List<Double>> seoul = List.of(
                List.of(126.9780, 37.5665),
                List.of(127.0374, 37.5445));

        LineString line = WalkPath.toLineString(seoul);

        assertThat(line.getCoordinateN(0).x)
                .as("x 가 경도다. 뒤집으면 지도에 엉뚱한 곳이 찍힌다")
                .isEqualTo(126.9780);
        assertThat(line.getCoordinateN(0).y).isEqualTo(37.5665);
        assertThat(line.getSRID()).isEqualTo(WalkPath.SRID);

        assertThat(WalkPath.toPoints(line))
                .as("왕복해도 순서가 그대로여야 한다")
                .isEqualTo(seoul);
    }

    @Test
    @DisplayName("뒤집혀 오면 거절한다 — 위도는 ±90 을 넘을 수 없다")
    void rejectsFlippedCoordinates() {
        // 앱이 NLatLng(위도, 경도) 를 그대로 실으면 이 모양이 된다.
        List<List<Double>> flipped = List.of(
                List.of(37.5665, 126.9780),
                List.of(37.5445, 127.0374));

        assertThatThrownBy(() -> WalkPath.toLineString(flipped))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("[경도, 위도]");
    }

    @Test
    @DisplayName("적도 근처는 뒤집혀도 안 걸린다 — 이 검사는 그물이지 보증이 아니다")
    void cannotDetectFlipsNearTheEquator() {
        // 싱가포르 근처: 경도 103.8, 위도 1.35. 뒤집으면 (1.35, 103.8) 인데
        // 둘째 값 103.8 > 90 이라 이건 걸린다. 그런데 둘 다 90 미만인 좌표는 못 잡는다.
        List<List<Double>> bothSmall = List.of(
                List.of(10.5, 20.3),
                List.of(10.6, 20.4));

        LineString line = WalkPath.toLineString(bothSmall);

        assertThat(line)
                .as("숫자만 보고는 어느 쪽이 위도인지 알 수 없다. 이 한계를 알고 쓴다")
                .isNotNull();
    }

    @Test
    @DisplayName("점이 2개 미만이면 경로 없이 저장한다 — LINESTRING 은 점 하나로 만들 수 없다")
    void tooFewPointsBecomeNoPath() {
        assertThat(WalkPath.toLineString(null)).isNull();
        assertThat(WalkPath.toLineString(List.of())).isNull();
        assertThat(WalkPath.toLineString(List.of(List.of(126.9780, 37.5665))))
                .as("시작점을 두 번 넣어 길이 0 짜리 선을 만들지 않는다 — 지도에 점이 찍힌다")
                .isNull();
    }

    @Test
    @DisplayName("모양이 계약과 다르면 거절한다")
    void rejectsMalformedPoints() {
        assertThatThrownBy(() -> WalkPath.toLineString(List.of(
                List.of(126.9780), List.of(127.0374, 37.5445))))
                .isInstanceOf(IllegalArgumentException.class);

        assertThatThrownBy(() -> WalkPath.toLineString(List.of(
                List.of(126.9780, 37.5665, 12.0), List.of(127.0374, 37.5445))))
                .isInstanceOf(IllegalArgumentException.class);

        List<List<Double>> withNull = new ArrayList<>();
        withNull.add(Arrays.asList(126.9780, null));
        withNull.add(List.of(127.0374, 37.5445));
        assertThatThrownBy(() -> WalkPath.toLineString(withNull))
                .isInstanceOf(IllegalArgumentException.class);

        assertThatThrownBy(() -> WalkPath.toLineString(List.of(
                List.of(200.0, 37.5665), List.of(127.0374, 37.5445))))
                .as("경도는 ±180 을 넘을 수 없다")
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("점 수에 상한이 있다 — 없으면 요청 하나가 임의 크기의 행을 만든다")
    void capsThePointCount() {
        List<List<Double>> tooMany = new ArrayList<>();
        for (int i = 0; i <= WalkPath.MAX_POINTS; i++) {
            tooMany.add(List.of(126.9780 + i * 1e-6, 37.5665));
        }

        assertThatThrownBy(() -> WalkPath.toLineString(tooMany))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining(String.valueOf(WalkPath.MAX_POINTS));
    }

    @Test
    @DisplayName("경로가 없으면 null 로 되돌린다 — 빈 배열이 아니다")
    void nullPathStaysNull() {
        assertThat(WalkPath.toPoints(null))
                .as("빈 배열은 '경로가 0점이다', null 은 '경로가 없다' 로 앱에서 다르게 읽힌다")
                .isNull();
    }
}
