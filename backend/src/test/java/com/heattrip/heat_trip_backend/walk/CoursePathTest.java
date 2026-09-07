package com.heattrip.heat_trip_backend.walk;

import com.heattrip.heat_trip_backend.walk.course.CoursePath;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 코스의 선 다듬기 — 이슈 #339.
 *
 * <p>여기서 재는 것은 하나다: <b>집 앞이 남지 않는가.</b> 자르는 기준이 점의 개수가 아니라
 * 거리라는 것, 짧은 산책은 코스가 되지 않는다는 것, 그리고 자른 뒤에도 선이 선으로 남는다는 것.
 */
class CoursePathTest {

    /** 서울숲 근처에서 동쪽으로 {@code stepM}m 씩 {@code count} 개. */
    private static List<List<Double>> line(int count, double stepM) {
        // 위도 37.5 에서 경도 1도는 약 88,000m 다. 그 비율로 걸음을 만든다.
        double stepLng = stepM / 88_000.0;
        List<List<Double>> points = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            points.add(List.of(127.0400 + stepLng * i, 37.5445));
        }
        return points;
    }

    @Test
    @DisplayName("양 끝 100m 를 버린다 — 집 앞이 남지 않는다")
    void trimsAHundredMetersFromEachEnd() {
        // 10m 씩 61점 = 600m
        List<List<Double>> trimmed = CoursePath.trimEnds(line(61, 10));

        assertThat(trimmed).isNotNull();
        assertThat(CoursePath.lengthMeters(trimmed))
                .as("600m 에서 앞뒤 100m 씩을 버리면 400m 쯤 남는다")
                .isBetween(380.0, 420.0);
        assertThat(trimmed.getFirst())
                .as("시작점이 원래 시작점이 아니다")
                .isNotEqualTo(line(61, 10).getFirst());
        assertThat(trimmed.getLast()).isNotEqualTo(line(61, 10).getLast());
    }

    @Test
    @DisplayName("점이 드문 산책도 같은 거리만큼 잘린다 — 개수가 아니라 거리가 기준이다")
    void trimsByDistanceNotByPointCount() {
        // 50m 씩 13점 = 600m. 앞의 두 점이면 이미 100m 다.
        List<List<Double>> sparse = CoursePath.trimEnds(line(13, 50));

        assertThat(sparse).isNotNull();
        assertThat(CoursePath.lengthMeters(sparse)).isBetween(380.0, 420.0);
    }

    @Test
    @DisplayName("300m 가 안 되면 코스가 아니다 — 자르고 나면 선이 남지 않는다")
    void refusesShortWalks() {
        assertThat(CoursePath.trimEnds(line(21, 10)))
                .as("200m 는 앞뒤를 자르면 아무것도 없다")
                .isNull();
        assertThat(CoursePath.trimEnds(line(26, 10)))
                .as("250m 도 남는 것이 50m 뿐이라 선이라 하기 어렵다")
                .isNull();
        assertThat(CoursePath.trimEnds(line(31, 10)))
                .as("300m 면 100m 가 남아 코스가 된다")
                .isNotNull();
    }

    @Test
    @DisplayName("점이 둘 이하거나 없으면 null — 지어내지 않는다")
    void returnsNullForDegenerateInput() {
        assertThat(CoursePath.trimEnds(null)).isNull();
        assertThat(CoursePath.trimEnds(List.of())).isNull();
        assertThat(CoursePath.trimEnds(List.of(List.of(127.04, 37.54)))).isNull();
        assertThat(CoursePath.trimEnds(line(2, 10))).isNull();
    }

    @Test
    @DisplayName("길이 재기 — 점이 하나면 0, 둘이면 그 사이")
    void measuresLength() {
        assertThat(CoursePath.lengthMeters(List.of())).isZero();
        assertThat(CoursePath.lengthMeters(line(1, 10))).isZero();
        assertThat(CoursePath.lengthMeters(line(2, 100))).isBetween(95.0, 105.0);
    }
}
