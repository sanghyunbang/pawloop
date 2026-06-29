package com.heattrip.heat_trip_backend.bookmark.dto;

import com.heattrip.heat_trip_backend.bookmark.entity.Collection;
import lombok.*;

@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class CollectionResponse {
    private Long id;
    private String name;
    private long count; // 아이템 개수
    private String latestItemContentId; // 최신 아이템(이미지 URL은 클라이언트에서 resolve)

    public static CollectionResponse of(Collection c, long count, String latestContentId) {
        return CollectionResponse.builder()
                .id(c.getId())
                .name(c.getName())
                .count(count)
                .latestItemContentId(latestContentId)
                .build();
    }
}
