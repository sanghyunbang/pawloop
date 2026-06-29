package com.heattrip.heat_trip_backend.explore.dto;

import java.util.List;

import lombok.AllArgsConstructor;
import lombok.Getter;

/**
 * Cursor(무한 스크롤) 응답 포맷.
 * - nextCursor: 다음 페이지를 요청할 때 필요한 토큰(마지막 항목의 정렬키 기반)
 * - hasNext: 다음 페이지 존재 여부
 */

 @Getter
@AllArgsConstructor
public class CursorPageResponse<T> {
    private List<T> items;
    private String nextCursor;
    private boolean hasNext;
}
