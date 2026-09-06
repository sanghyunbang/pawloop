package com.heattrip.heat_trip_backend.place.dto;

import com.fasterxml.jackson.annotation.JsonRawValue;

/**
 * 계약의 {@code TrailRoute} — 산책로 코스 하나의 선. 이슈 #291.
 *
 * <p>{@code points} 는 저장된 JSON 문자열을 <b>그대로</b> 내보낸다({@link JsonRawValue}).
 * 300 점을 파싱해서 다시 직렬화할 이유가 없다 — 카탈로그 응답과 같은 원칙이다.
 */
public record TrailRouteDto(
        String courseId,
        String name,
        int lengthM,
        int pointCount,
        @JsonRawValue String points) {
}
