package com.heattrip.heat_trip_backend.walk.course;

import com.heattrip.heat_trip_backend.walk.service.WalkPath;

import java.time.Instant;
import java.util.Arrays;
import java.util.List;

/**
 * 코스 하나 — 이슈 #339. 계약의 {@code Course}.
 *
 * <p>{@code path} 는 <b>이미 잘라 낸 선</b>이다. 원래 산책의 선은 이 응답 어디에도 없다 —
 * 코스를 받는 쪽이 집 앞을 복원할 수 없어야 한다.
 *
 * @param mine 내 코스인가. 공개 목록에서 내 것을 가려 주는 데 쓴다
 */
public record CourseResponse(
        Long id,
        Long walkId,
        String name,
        String note,
        List<String> tags,
        List<List<Double>> path,
        int distanceM,
        int durationS,
        String visibility,
        boolean mine,
        Instant createdAt) {

    /** 목록용 — 선을 빼고 만든다. 시작점만 준다(지도에 점을 찍는 데 그것이면 된다). */
    public static CourseResponse summary(Course course, long viewerId) {
        List<List<Double>> full = WalkPath.toPoints(course.getPath());
        return new CourseResponse(
                course.getId(),
                course.getWalkId(),
                course.getName(),
                course.getNote(),
                parseTags(course.getTags()),
                full == null || full.isEmpty() ? null : List.of(full.getFirst()),
                course.getDistanceM(),
                course.getDurationS(),
                course.getVisibility(),
                course.getUserId() == viewerId,
                course.createdAtInstant());
    }

    /** 상세용 — 선을 실어 만든다. */
    public static CourseResponse withPath(Course course, long viewerId) {
        return new CourseResponse(
                course.getId(),
                course.getWalkId(),
                course.getName(),
                course.getNote(),
                parseTags(course.getTags()),
                WalkPath.toPoints(course.getPath()),
                course.getDistanceM(),
                course.getDurationS(),
                course.getVisibility(),
                course.getUserId() == viewerId,
                course.createdAtInstant());
    }

    /** 저장은 콤마 하나로 한다 — 값이 셋으로 닫혀 있어 표를 나눌 이유가 없다. */
    static List<String> parseTags(String stored) {
        if (stored == null || stored.isBlank()) {
            return List.of();
        }
        return Arrays.stream(stored.split(","))
                .map(String::strip)
                .filter(tag -> !tag.isEmpty())
                .toList();
    }
}
