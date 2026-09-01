package com.heattrip.heat_trip_backend.walk.dto;

import java.util.List;

/**
 * 계약의 {@code Page} 봉투에 {@code Walk} 를 담은 것 — 이슈 #145.
 *
 * @param nextCursor 마지막 페이지에서 {@code null} 이다. 계약이 그래서 이 필드를
 *                   {@code required} 에 넣지 않았다
 */
public record WalkPageResponse(
        List<WalkResponse> items,
        String nextCursor,
        boolean hasMore) {
}
