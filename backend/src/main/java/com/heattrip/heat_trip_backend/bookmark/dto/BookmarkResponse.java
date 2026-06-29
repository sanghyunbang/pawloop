package com.heattrip.heat_trip_backend.bookmark.dto;

import com.heattrip.heat_trip_backend.bookmark.entity.Bookmark;
import lombok.*;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class BookmarkResponse {
    private String contentId;

    public static BookmarkResponse from(Bookmark b) {
        return BookmarkResponse.builder()
                .contentId(b.getContentId())
                .build();
    }
}
