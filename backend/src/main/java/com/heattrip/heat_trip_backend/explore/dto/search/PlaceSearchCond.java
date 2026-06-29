package com.heattrip.heat_trip_backend.explore.dto.search;

import java.util.List;

/**
 * 검색 조건 DTO (검색 기능 전용 패키지로 분리).
 * - q: 키워드 (title, cat1/2/3, cat3Name LIKE) ※C-1
 * - contentTypeId: 선택 필터 (DB는 VARCHAR이므로 문자열 비교 사용) ※C-2
 * - cat3: 선택 필터 (A02010800 같은 코드 리스트)
 * - emotionCategoryId: 선택 필터 (1~18) — cat3_category_mapping EXISTS ※C-3
 * - page/size/sort: 페이지네이션/정렬
 */
public record PlaceSearchCond(
    String q,
    Integer contentTypeId,
    List<String> cat3,
    Integer emotionCategoryId,
    Integer page,
    Integer size,
    String sort
) {
    public int limit()  { return (size==null || size<1 || size>100) ? 20 : size; }
    public int offset() { return Math.max(page==null?0:page, 0) * limit(); }
}
