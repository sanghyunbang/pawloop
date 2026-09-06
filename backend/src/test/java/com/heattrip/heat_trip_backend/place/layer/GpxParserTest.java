package com.heattrip.heat_trip_backend.place.layer;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;

/** GPX 읽기·줄이기 — 이슈 #291. */
class GpxParserTest {

    private static final String GPX = """
            <?xml version="1.0" encoding="UTF-8"?>
            <gpx version="1.1" creator="durunubi" xmlns="http://www.topografix.com/GPX/1/1">
              <trk><name>서울숲 둘레</name><trkseg>
                <trkpt lat="37.5445" lon="127.0374"><ele>20</ele></trkpt>
                <trkpt lat="37.5449" lon="127.0379"></trkpt>
                <trkpt lat="37.5453" lon="127.0385"/>
                <trkpt lat="abc" lon="127.0390"/>
                <trkpt lat="37.5455" lon="127.0392"/>
              </trkseg></trk>
            </gpx>
            """;

    @Test
    @DisplayName("trkpt 를 순서대로 [경도, 위도] 로 읽고 깨진 점은 건너뛴다")
    void readsTrackPointsAsLngLat() throws Exception {
        List<double[]> points = GpxParser.trackPoints(GPX);

        assertThat(points).hasSize(4);
        assertThat(points.get(0)[0]).as("경도가 먼저다 — 계약의 Walk.path 와 같다").isEqualTo(127.0374);
        assertThat(points.get(0)[1]).isEqualTo(37.5445);
        assertThat(points.get(3)[1]).isEqualTo(37.5455);
    }

    @Test
    @DisplayName("trkpt 가 없으면 rtept 를 본다")
    void fallsBackToRoutePoints() throws Exception {
        String route = """
                <gpx><rte><rtept lat="37.1" lon="127.1"/><rtept lat="37.2" lon="127.2"/></rte></gpx>
                """;
        assertThat(GpxParser.trackPoints(route)).hasSize(2);
    }

    @Test
    @DisplayName("점을 상한 아래로 줄이되 첫 점과 끝 점은 남긴다")
    void simplifiesToTheCap() {
        List<double[]> noisy = new ArrayList<>();
        for (int i = 0; i <= 2000; i++) {
            // 북동쪽으로 가는 선에 작은 지그재그
            noisy.add(new double[] {127.0 + i * 0.0001, 37.5 + i * 0.0001 + (i % 2 == 0 ? 0.00001 : -0.00001)});
        }
        List<double[]> reduced = GpxParser.simplify(noisy, 50);

        assertThat(reduced.size()).isBetween(2, 50);
        assertThat(reduced.get(0)).containsExactly(noisy.get(0));
        assertThat(reduced.get(reduced.size() - 1)).containsExactly(noisy.get(noisy.size() - 1));
    }

    @Test
    @DisplayName("상한 안이면 그대로 돌려준다 — 줄일 것이 없다")
    void leavesShortLinesAlone() {
        List<double[]> line = List.of(new double[] {127.0, 37.5}, new double[] {127.1, 37.6}, new double[] {127.2, 37.7});
        assertThat(GpxParser.simplify(line, 300)).isSameAs(line);
    }

    @Test
    @DisplayName("길이는 하버사인 누적이다 — 위도 1도가 약 111km")
    void measuresLength() {
        List<double[]> line = List.of(new double[] {127.0, 37.0}, new double[] {127.0, 38.0});
        assertThat(GpxParser.lengthMeters(line)).isCloseTo(111_195, within(300.0));
    }

    @Test
    @DisplayName("JSON 은 [[경도,위도],…] 이고 소수 여섯째 자리에서 끊는다")
    void writesCompactJson() {
        String json = GpxParser.toJson(List.of(new double[] {127.03741234567, 37.5445}, new double[] {127.0, 37.0}));
        assertThat(json).isEqualTo("[[127.037412,37.5445],[127.0,37.0]]");
    }
}
