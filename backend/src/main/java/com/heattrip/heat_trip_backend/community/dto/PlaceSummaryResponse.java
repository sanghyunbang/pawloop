package com.heattrip.heat_trip_backend.community.dto;

/**
 * 장소 머리의 숫자 셋 — 이슈 #729. {@code GET /api/community/places/{contentId}/summary}.
 *
 * <p>글은 공개라 게스트도 본다. 셋 다 <b>세는 것뿐</b>이라 누가 썼는지 · 어디를 걸었는지는 안 나간다.
 *
 * @param posts  그 장소를 골라 쓴 글의 수({@code Post.contentId})
 * @param photos 그 글들에 붙은 사진·영상의 수
 * @param walks  그 장소에서 한 산책의 수({@code walk.place_content_id}) — 모든 사람의 것
 */
public record PlaceSummaryResponse(long posts, long photos, long walks) {
}
