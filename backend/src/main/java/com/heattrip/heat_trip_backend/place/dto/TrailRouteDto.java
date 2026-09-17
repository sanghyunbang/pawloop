package com.heattrip.heat_trip_backend.place.dto;

import java.util.List;

import com.fasterxml.jackson.annotation.JsonIgnore;
import com.fasterxml.jackson.annotation.JsonRawValue;

/**
 * 계약의 {@code TrailRoute} — 산책로 코스 하나의 선. 이슈 #291.
 *
 * <p>{@code points} 는 저장된 JSON 문자열을 <b>그대로</b> 내보낸다({@link JsonRawValue}).
 * 300 점을 파싱해서 다시 직렬화할 이유가 없다 — 카탈로그 응답과 같은 원칙이다.
 *
 * <h2>선이 없는 코스도 여기로 답한다 — 이슈 #619</h2>
 * <p>동네 길(#346)은 원본에 좌표가 없어 그릴 선이 없다. 예전에는 그 코스의 이 경로가
 * <b>404</b> 였고, 앱은 {@code hasTrailRoute} 로 아예 안 물었다. 그래서 사용자가 산책로를
 * 눌러도 <b>아무 일도 안 났다</b>.
 *
 * <p>지금은 묻는다. 선이 있으면 {@link #points} 로, 없으면 {@link #waypoints} 로 답한다 —
 * 둘 중 하나는 늘 찬다. "이 길이 어디로 가는가" 에 답할 것이 있는데 404 로 입을 닫을
 * 이유가 없다.
 *
 * <pre>
 *   두루누비   points 300개 · waypoints 빈 목록
 *   동네 길    points 빈 배열 · waypoints 6개쯤
 * </pre>
 */
public record TrailRouteDto(
        String courseId,
        String name,
        int lengthM,
        int pointCount,
        @JsonRawValue String points,
        List<String> waypoints) {

    /** 선이 없는 코스의 {@code points} — 빈 배열이다. {@code null} 이면 앱이 파싱에서 갈린다. */
    public static final String NO_POINTS = "[]";

    /**
     * 선이 있는 코스 — 두루누비. 경유지는 그쪽 원본에 그런 모양으로 없다.
     *
     * <p>선이 있으면 경유지 이름은 덧이다 — 지도에 그려진 길이 이미 어디로 가는지 말한다.
     */
    public static TrailRouteDto ofLine(String courseId, String name, int lengthM,
                                       int pointCount, String points) {
        return new TrailRouteDto(courseId, name, lengthM, pointCount, points, List.of());
    }

    /**
     * 선이 없는 코스 — 동네 길. 거쳐 가는 곳의 <b>이름</b>만 있다.
     *
     * <p>이 이름들을 좌표로 바꿔 이으면 실제로 걷는 길이 아닌 직선이 된다. 그래서 바꾸지
     * 않는다 — #619 에서 그 방법을 일부러 버렸다.
     */
    public static TrailRouteDto ofStops(String courseId, String name, int lengthM,
                                        List<String> waypoints) {
        return new TrailRouteDto(courseId, name, lengthM, 0, NO_POINTS, List.copyOf(waypoints));
    }

    /**
     * 지도에 그릴 선이 있나. 없으면 화면은 시작 지점 하나만 보여 준다.
     *
     * <p>{@code @JsonIgnore} 는 본문에 {@code line} 이라는 없는 칸이 생기지 않게 하는 것이다.
     * 잭슨은 {@code has…} 를 접두어로 안 보지만, 계약에 없는 칸은 <b>실수로도</b> 나가면
     * 안 된다 — {@code PlacesContractSpecTest} 가 칸 이름을 정확히 맞춘다.
     */
    @JsonIgnore
    public boolean hasLine() {
        return pointCount >= 2;
    }
}
