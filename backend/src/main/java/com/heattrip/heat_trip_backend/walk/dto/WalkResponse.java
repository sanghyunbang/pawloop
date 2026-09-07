package com.heattrip.heat_trip_backend.walk.dto;

import com.heattrip.heat_trip_backend.walk.entity.Walk;
import com.heattrip.heat_trip_backend.walk.service.WalkPath;

import java.time.Instant;
import java.util.List;

/**
 * 계약의 {@code Walk} — 이슈 #145.
 *
 * @param path 목록 응답에서는 <b>항상 {@code null}</b> 이다. 한 산책의 경로가 수천 점이라
 *             목록에 실으면 응답이 메가바이트가 된다. 상세에서만 준다 — {@link #withPath}
 * @param clientWalkId 되돌려 주는 이유는 앱이 <b>전송 대기 큐의 어느 항목이 저장된 것인지</b>
 *                     맞춰 볼 수 있어야 하기 때문이다
 */
public record WalkResponse(
        Long id,
        Long dogId,
        String clientWalkId,
        Instant startedAt,
        Instant endedAt,
        int distanceM,
        int durationS,
        List<List<Double>> path,
        String memo,
        String weather,

        /**
         * 어디를 걸었나 (#338). 카탈로그에서 고른 곳이면 셋 다 있고, 손으로 이름만 적었으면
         * {@code source}·{@code contentId} 가 {@code null} 이다. 아무것도 안 붙였으면 이 필드가
         * {@code null} 이다 — 빈 객체를 주지 않는다.
         */
        WalkPlace place) {

    /**
     * 계약의 {@code Walk.place}. {@code PlaceRef} 와 같은 모양이되 <b>출처와 id 가 없을 수
     * 있다</b> — 카탈로그에 없는 곳을 손으로 적은 경우다.
     */
    public record WalkPlace(String source, String contentId, String title) {

        /** 이름이 없으면 장소가 없는 것이다 — 출처만 있는 행은 만들지 않는다. */
        static WalkPlace of(Walk walk) {
            if (walk.getPlaceName() == null || walk.getPlaceName().isBlank()) {
                return null;
            }
            return new WalkPlace(walk.getPlaceSource(), walk.getPlaceContentId(), walk.getPlaceName());
        }
    }

    /** 목록용 — 경로를 빼고 만든다. */
    public static WalkResponse summary(Walk walk) {
        return new WalkResponse(
                walk.getId(),
                walk.getDog().getId(),
                walk.getClientWalkId(),
                walk.startedAtInstant(),
                walk.endedAtInstant(),
                walk.getDistanceM(),
                walk.getDurationS(),
                null,
                walk.getMemo(),
                walk.getWeather(),
                WalkPlace.of(walk));
    }

    /** 상세용 — 경로를 실어 만든다. */
    public static WalkResponse withPath(Walk walk) {
        return new WalkResponse(
                walk.getId(),
                walk.getDog().getId(),
                walk.getClientWalkId(),
                walk.startedAtInstant(),
                walk.endedAtInstant(),
                walk.getDistanceM(),
                walk.getDurationS(),
                WalkPath.toPoints(walk.getPath()),
                walk.getMemo(),
                walk.getWeather(),
                WalkPlace.of(walk));
    }
}
