package com.heattrip.heat_trip_backend.community.dto;

import jakarta.validation.constraints.NotBlank;

/**
 * 댓글 작성 요청. 계약에는 별도 컴포넌트가 아니라 <b>인라인 스키마</b>로 있다 —
 * {@code required: [body]} 하나뿐이다.
 */
public record CommentRequest(
        @NotBlank(message = "댓글을 적어 주세요.")
        String body) {
}
