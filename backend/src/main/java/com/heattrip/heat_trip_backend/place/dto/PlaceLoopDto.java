package com.heattrip.heat_trip_backend.place.dto;

import com.fasterxml.jackson.annotation.JsonRawValue;

/**
 * 장소에서 출발해 돌아오는 추천 산책 코스 — 이슈 #725. {@code GET /api/places/{contentId}/loop}.
 *
 * <p><b>못 줄 때도 200 이다</b> — {@code available=false} 와 {@code reason}. 카탈로그가 예산
 * 소진에 {@code []} 를 주는 것과 같은 태도다: 키가 없거나 하루 한도를 다 썼거나 바깥이 죽은 것은
 * 오류가 아니라 "지금은 없음" 이고, 그때 5xx 를 내면 정상 상황이 경보가 된다(#657).
 *
 * @param contentId  카탈로그 장소 id — 시작점이자 도착점
 * @param targetM    부탁한 길이(m). 500 ~ 10,000, 500 단위로 맞춘 값
 * @param available  코스를 줄 수 있는가
 * @param reason     못 줄 때만: {@code nokey} · {@code budget} · {@code upstream} · {@code busy}
 * @param distanceM  실제 길이(m). 없으면 {@code null}
 * @param durationS  도보 예상 시간(초). 없으면 {@code null}
 * @param pointCount {@code points} 의 길이. 없으면 0
 * @param points     {@code [[경도, 위도], …]} — {@code Walk.path}·{@code TrailRoute.points} 와 같은 순서. 없으면 {@code []}
 */
public record PlaceLoopDto(
        String contentId,
        int targetM,
        boolean available,
        String reason,
        Integer distanceM,
        Integer durationS,
        int pointCount,
        @JsonRawValue String points) {

    public static final String NO_POINTS = "[]";

    public static PlaceLoopDto ready(String contentId, int targetM, int distanceM, int durationS,
                                     int pointCount, String points) {
        return new PlaceLoopDto(contentId, targetM, true, null, distanceM, durationS, pointCount, points);
    }

    public static PlaceLoopDto unavailable(String contentId, int targetM, String reason) {
        return new PlaceLoopDto(contentId, targetM, false, reason, null, null, 0, NO_POINTS);
    }
}
