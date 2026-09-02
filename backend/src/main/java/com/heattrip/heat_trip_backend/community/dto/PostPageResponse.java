package com.heattrip.heat_trip_backend.community.dto;

import java.util.List;

/**
 * 글 목록 한 장 — 계약의 {@code Page} + {@code items}.
 *
 * <p>{@code nextCursor} 는 마지막 장에서 {@code null} 이다 — 계약이 그래서 {@code required} 에
 * 안 넣었다.
 */
public record PostPageResponse(List<PostResponse> items, String nextCursor, boolean hasMore) {
}
