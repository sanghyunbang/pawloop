package com.heattrip.heat_trip_backend.social.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

/** 댓글 작성 요청 본문. body 필수, handle 선택(null이면 익명). */
@Getter
@Setter
@NoArgsConstructor
public class CommentRequest {
    private String body;
    private String handle;
}
