package com.heattrip.heat_trip_backend.bookmark.dto;

import com.heattrip.heat_trip_backend.bookmark.entity.CollectionItem;
import lombok.*;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CollectionItemResponse {
    private String contentId;

    public static CollectionItemResponse from(CollectionItem ci) {
        return CollectionItemResponse.builder()
                .contentId(ci.getContentId())
                .build();
    }
}
