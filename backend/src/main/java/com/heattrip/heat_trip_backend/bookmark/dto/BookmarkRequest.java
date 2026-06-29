package com.heattrip.heat_trip_backend.bookmark.dto;

import lombok.*;

/** 북마크 추가 요청 */
@Getter @Setter @NoArgsConstructor @AllArgsConstructor
public class BookmarkRequest {
    private String contentId;
    /** 선택: 특정 컬렉션에도 함께 추가하고 싶다면 지정 */
    private String collectionId;
}
