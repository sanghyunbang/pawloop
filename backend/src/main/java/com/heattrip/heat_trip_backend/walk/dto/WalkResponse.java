package com.heattrip.heat_trip_backend.walk.dto;

import com.heattrip.heat_trip_backend.walk.entity.Walk;
import com.heattrip.heat_trip_backend.walk.service.WalkPath;

import java.time.Instant;
import java.util.List;
import java.util.stream.Stream;

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

        /**
         * <b>대표 아이</b>. {@link #dogIds} 의 첫 번째와 같다 — 앱이 고른 목록의 첫 마리다.
         *
         * <p>여러 마리가 된 뒤에도 이 필드를 지우지 않았다(#343). 이미 나가 있는 앱이 이
         * 값으로 화면을 그리고 있고, 멱등키 {@code uq_walk_client (dog_id, client_walk_id)}
         * 의 앞자리이며, 소유권이 이 연관을 타고 {@code dog.user_id} 로 간다.
         */
        Long dogId,

        /**
         * 함께 나간 아이들 — 이슈 #343. <b>항상 한 개 이상</b>이고 첫 번째가 {@link #dogId} 다.
         *
         * <p>한 마리만 데리고 나갔으면 원소가 하나다 — 빈 배열이나 {@code null} 이 아니다.
         * "여러 마리일 때만 있는 필드" 로 두면 화면이 두 갈래를 만들고, 그중 하나가 언젠가
         * 안 그린다.
         */
        List<Long> dogIds,
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
     * 함께 나간 아이들. 대표 아이를 <b>맨 앞</b>에 놓는다 (#343).
     *
     * <p>이음매 표({@code walk_dog})의 순서는 DB 가 정하는 것이라 대표 아이가 가운데에
     * 올 수 있다. 계약이 "첫 번째가 dogId" 라고 적었으므로 여기서 세운다.
     *
     * <p>33_walk_dog.sql 이전에 쌓인 행이 채워지지 않은 DB 를 만나도 <b>빈 배열을 주지
     * 않는다</b> — 그때는 대표 아이 하나짜리 목록이 된다. 화면이 "아이가 없는 산책" 이라는,
     * 있을 수 없는 상태를 그리지 않게 한다.
     */
    private static List<Long> dogIdsOf(Walk walk) {
        Long lead = walk.getDog().getId();
        List<Long> rest = walk.dogIds().stream().filter(id -> !id.equals(lead)).toList();
        return Stream.concat(Stream.of(lead), rest.stream()).toList();
    }

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
                dogIdsOf(walk),
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
                dogIdsOf(walk),
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
