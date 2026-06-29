package com.heattrip.heat_trip_backend.social.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** 카드 공유 요청 본문. moodKey/body 필수, 나머지는 선택. */
@Getter
@Setter
@NoArgsConstructor
public class ShareCardRequest {
    private String moodKey;
    private String body;
    private String placeName;
    private Long placeId;
    private String handle;
}
