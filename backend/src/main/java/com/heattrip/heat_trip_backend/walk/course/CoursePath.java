package com.heattrip.heat_trip_backend.walk.course;

import java.util.ArrayList;
import java.util.List;

/**
 * 코스의 선 다듬기 — 이슈 #339.
 *
 * <p><b>시작과 끝을 잘라 낸다.</b> 산책은 대개 집 앞에서 시작해 집 앞에서 끝난다. 그 선을
 * 그대로 공개하면 코스를 나누는 일이 곧 사는 곳을 알리는 일이 된다. 그래서 양 끝
 * {@value #TRIM_METERS}m 를 버리고 남은 가운데만 코스로 만든다.
 *
 * <p>자르는 기준은 <b>점의 개수가 아니라 거리</b>다. 5m 마다 한 점이 찍히는 산책과 신호를
 * 못 잡아 드문드문 찍힌 산책이 같은 규칙으로 잘려야 한다.
 *
 * <p>남은 길이가 {@value #MIN_REMAINING_METERS}m 보다 짧으면 코스로 만들지 않는다. 양 끝을
 * 자르고 나면 사실상 선이 아니고, 그런 코스는 지도에서 점 하나로 보인다. 결국 <b>300m 쯤은
 * 걸어야</b> 코스가 된다 — 그 사실을 앱이 미리 말한다.
 */
public final class CoursePath {

    /** 양 끝에서 잘라 내는 거리(m). */
    public static final int TRIM_METERS = 100;

    /** 자르고 남아야 하는 최소 길이(m). */
    public static final int MIN_REMAINING_METERS = 100;

    private static final double EARTH_RADIUS_M = 6_371_000;

    private CoursePath() {
    }

    /**
     * 양 끝 {@value #TRIM_METERS}m 를 버린 선. 남길 것이 없으면 {@code null}.
     *
     * @param points 계약의 {@code [[경도, 위도], ...]}
     */
    public static List<List<Double>> trimEnds(List<List<Double>> points) {
        if (points == null || points.size() < 2) {
            return null;
        }

        int from = advance(points, 0, 1);
        int to = advance(points, points.size() - 1, -1);
        if (to - from < 1) {
            return null;
        }

        List<List<Double>> trimmed = new ArrayList<>(points.subList(from, to + 1));
        return lengthMeters(trimmed) < MIN_REMAINING_METERS ? null : trimmed;
    }

    /**
     * 점을 [maxPoints] 개 이하로 줄인다 — 카드에 그릴 그림용 (#339).
     *
     * <p>모양만 남기면 되는 자리라 <b>같은 간격으로 골라낸다</b>(Douglas-Peucker 를 쓰지
     * 않는다). 시작점과 끝점은 반드시 남긴다 — 그 둘이 없으면 선이 다른 곳에서 시작해
     * 다른 곳에서 끝나는 것처럼 보인다.
     *
     * <p>피드 응답에 300점짜리 선을 스무 개 싣지 않기 위한 것이고, 상세에서 부르는
     * {@code GET /api/courses/&#123;id&#125;} 는 여전히 온전한 선을 준다.
     */
    public static List<List<Double>> simplify(List<List<Double>> points, int maxPoints) {
        if (points == null || points.size() <= maxPoints || maxPoints < 2) {
            return points;
        }
        List<List<Double>> out = new ArrayList<>(maxPoints);
        double step = (points.size() - 1) / (double) (maxPoints - 1);
        for (int i = 0; i < maxPoints - 1; i++) {
            out.add(points.get((int) Math.round(i * step)));
        }
        out.add(points.getLast());
        return out;
    }

    /** 선의 길이(m). 점이 하나 이하면 0 이다. */
    public static double lengthMeters(List<List<Double>> points) {
        if (points == null || points.size() < 2) {
            return 0;
        }
        double total = 0;
        for (int i = 1; i < points.size(); i++) {
            total += distanceMeters(points.get(i - 1), points.get(i));
        }
        return total;
    }

    /**
     * {@code start} 에서 {@code step} 방향으로 {@value #TRIM_METERS}m 를 지난 첫 점의 자리.
     *
     * <p>경계를 넘어가면 마지막 자리를 준다 — 호출부가 {@code to - from} 으로 걸러 낸다.
     */
    private static int advance(List<List<Double>> points, int start, int step) {
        double walked = 0;
        int index = start;
        while (true) {
            int next = index + step;
            if (next < 0 || next >= points.size()) {
                return index;
            }
            walked += distanceMeters(points.get(index), points.get(next));
            index = next;
            if (walked >= TRIM_METERS) {
                return index;
            }
        }
    }

    /** 하버사인. {@code [경도, 위도]} 순서다 — 계약과 같다. */
    private static double distanceMeters(List<Double> a, List<Double> b) {
        double lat1 = Math.toRadians(a.get(1));
        double lat2 = Math.toRadians(b.get(1));
        double dLat = lat2 - lat1;
        double dLng = Math.toRadians(b.get(0) - a.get(0));
        double h = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 2 * EARTH_RADIUS_M * Math.asin(Math.min(1, Math.sqrt(h)));
    }
}
