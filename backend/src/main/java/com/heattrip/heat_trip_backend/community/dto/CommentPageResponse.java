package com.heattrip.heat_trip_backend.community.dto;

import java.util.List;

/**
 * 댓글 목록 한 장 — 계약의 {@code Page} + {@code items}.
 *
 * <p>2026-09 이전에는 벌거벗은 배열이었고 {@code cursor}/{@code limit} 파라미터조차 없었다.
 * 댓글은 인기글에서 무한정 커지는데 한 번에 전부 내려보내는 계약이었다(ADR-0017 규약 2).
 */
public record CommentPageResponse(List<CommentResponse> items, String nextCursor, boolean hasMore) {
}
