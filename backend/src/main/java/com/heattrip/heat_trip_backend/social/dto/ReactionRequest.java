package com.heattrip.heat_trip_backend.social.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** 리액션 토글 요청 본문. type 은 SAME | CHEER | CALM. */
@Getter
@Setter
@NoArgsConstructor
public class ReactionRequest {
    private String type;
}
