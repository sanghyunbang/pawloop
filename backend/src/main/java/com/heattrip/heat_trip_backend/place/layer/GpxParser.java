package com.heattrip.heat_trip_backend.place.layer;

import javax.xml.stream.XMLInputFactory;
import javax.xml.stream.XMLStreamConstants;
import javax.xml.stream.XMLStreamReader;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.List;

/**
 * GPX 파일에서 선을 꺼내고 줄인다 — 이슈 #291.
 *
 * <p>두루누비의 GPX 는 {@code <trkpt lat=".." lon="..">} 가 코스 하나에 수천 개다. 점 하나가
 * JSON 으로 30바이트쯤이라 그대로 두면 코스 하나가 100KB 를 넘고, 앱이 지도에 그릴 때도
 * 그만큼 무겁다. <b>Douglas–Peucker</b> 로 형태를 지키며 점을 줄인다 — 300 점이면 지도 배율
 * 어디서도 원본과 구분이 안 된다.
 *
 * <p>좌표 순서는 <b>{@code [경도, 위도]}</b> 다 — 앱의 산책 경로·계약의 {@code Walk.path} 와
 * 같은 순서다. GPX 의 {@code lat}/{@code lon} 을 여기서 뒤집는다.
 */
public final class GpxParser {

    private static final double EARTH_RADIUS_M = 6_371_000.0;

    private GpxParser() {
    }

    /**
     * 트랙 점을 순서대로. {@code trkpt} 가 하나도 없으면 {@code rtept} 를 본다.
     *
     * @return {@code [lng, lat]} 목록. 좌표가 깨진 점은 건너뛴다
     */
    public static List<double[]> trackPoints(String gpxXml) throws Exception {
        List<double[]> track = new ArrayList<>();
        List<double[]> route = new ArrayList<>();

        XMLInputFactory factory = XMLInputFactory.newFactory();
        factory.setProperty(XMLInputFactory.IS_SUPPORTING_EXTERNAL_ENTITIES, false);
        factory.setProperty(XMLInputFactory.SUPPORT_DTD, false);
        XMLStreamReader reader = factory.createXMLStreamReader(new StringReader(gpxXml));
        try {
            while (reader.hasNext()) {
                if (reader.next() != XMLStreamConstants.START_ELEMENT) {
                    continue;
                }
                String name = reader.getLocalName();
                if (!"trkpt".equals(name) && !"rtept".equals(name)) {
                    continue;
                }
                double[] point = point(reader.getAttributeValue(null, "lat"), reader.getAttributeValue(null, "lon"));
                if (point != null) {
                    ("trkpt".equals(name) ? track : route).add(point);
                }
            }
        } finally {
            reader.close();
        }
        return track.isEmpty() ? route : track;
    }

    private static double[] point(String lat, String lon) {
        if (lat == null || lon == null) {
            return null;
        }
        try {
            double y = Double.parseDouble(lat.strip());
            double x = Double.parseDouble(lon.strip());
            if (y < -90 || y > 90 || x < -180 || x > 180) {
                return null;
            }
            return new double[] {x, y};
        } catch (NumberFormatException e) {
            return null;
        }
    }

    /**
     * 점을 {@code maxPoints} 이하로 줄인다. 첫 점과 끝 점은 항상 남는다.
     *
     * <p>Douglas–Peucker 의 허용 오차를 이분 탐색한다 — 오차를 고정하면 짧은 코스는 3점,
     * 긴 코스는 2,000점이 된다. 우리가 지키려는 것은 오차가 아니라 <b>점 수</b>다.
     */
    public static List<double[]> simplify(List<double[]> points, int maxPoints) {
        if (points.size() <= Math.max(2, maxPoints)) {
            return points;
        }
        double low = 0.0;
        double high = 1.0; // 도 단위. 1° 면 무엇이든 2점이 된다
        List<double[]> best = List.of(points.get(0), points.get(points.size() - 1));
        for (int i = 0; i < 40; i++) {
            double mid = (low + high) / 2;
            List<double[]> candidate = douglasPeucker(points, mid);
            if (candidate.size() <= maxPoints) {
                best = candidate;
                high = mid;
            } else {
                low = mid;
            }
        }
        return best;
    }

    /** 표준 반복형 Douglas–Peucker. 허용 오차는 도 단위(경위도 평면 근사)다. */
    static List<double[]> douglasPeucker(List<double[]> points, double tolerance) {
        int n = points.size();
        if (n < 3) {
            return points;
        }
        boolean[] keep = new boolean[n];
        keep[0] = true;
        keep[n - 1] = true;
        java.util.ArrayDeque<int[]> stack = new java.util.ArrayDeque<>();
        stack.push(new int[] {0, n - 1});
        while (!stack.isEmpty()) {
            int[] range = stack.pop();
            int start = range[0];
            int end = range[1];
            double maxDistance = -1;
            int index = -1;
            for (int i = start + 1; i < end; i++) {
                double d = perpendicularDistance(points.get(i), points.get(start), points.get(end));
                if (d > maxDistance) {
                    maxDistance = d;
                    index = i;
                }
            }
            if (index > 0 && maxDistance > tolerance) {
                keep[index] = true;
                stack.push(new int[] {start, index});
                stack.push(new int[] {index, end});
            }
        }
        List<double[]> out = new ArrayList<>();
        for (int i = 0; i < n; i++) {
            if (keep[i]) {
                out.add(points.get(i));
            }
        }
        return out;
    }

    private static double perpendicularDistance(double[] p, double[] a, double[] b) {
        double dx = b[0] - a[0];
        double dy = b[1] - a[1];
        if (dx == 0 && dy == 0) {
            return Math.hypot(p[0] - a[0], p[1] - a[1]);
        }
        double t = ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / (dx * dx + dy * dy);
        t = Math.max(0, Math.min(1, t));
        double projX = a[0] + t * dx;
        double projY = a[1] + t * dy;
        return Math.hypot(p[0] - projX, p[1] - projY);
    }

    /** 선의 길이(m). 하버사인 누적이다. */
    public static double lengthMeters(List<double[]> points) {
        double total = 0;
        for (int i = 1; i < points.size(); i++) {
            total += haversine(points.get(i - 1), points.get(i));
        }
        return total;
    }

    private static double haversine(double[] a, double[] b) {
        double dLat = Math.toRadians(b[1] - a[1]);
        double dLng = Math.toRadians(b[0] - a[0]);
        double h = Math.sin(dLat / 2) * Math.sin(dLat / 2)
                + Math.cos(Math.toRadians(a[1])) * Math.cos(Math.toRadians(b[1]))
                * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return EARTH_RADIUS_M * 2 * Math.atan2(Math.sqrt(h), Math.sqrt(1 - h));
    }

    /** {@code [[lng,lat],...]} JSON. Jackson 없이 만든다 — 숫자 배열이라 손으로 쓰는 것이 빠르고 안전하다. */
    public static String toJson(List<double[]> points) {
        StringBuilder sb = new StringBuilder(points.size() * 24 + 2);
        sb.append('[');
        for (int i = 0; i < points.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            double[] p = points.get(i);
            sb.append('[').append(round(p[0])).append(',').append(round(p[1])).append(']');
        }
        return sb.append(']').toString();
    }

    /** 소수 여섯째 자리(약 0.1m). 그 아래는 GPS 잡음이고 바이트만 먹는다. */
    private static double round(double value) {
        return Math.round(value * 1_000_000d) / 1_000_000d;
    }
}
