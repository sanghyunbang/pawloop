package com.heattrip.heat_trip_backend.community.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

/**
 * 댓글 작성 요청. 계약에는 별도 컴포넌트가 아니라 <b>인라인 스키마</b>로 있다 —
 * {@code required: [body]} 하나뿐이다.
 *
 * <p>{@code PostRequest.body} 와 같은 이유로 상한이 있다 — 컬럼이 {@code TEXT} 라 안 막으면
 * {@code 65535}바이트까지 들어간다. 글보다 짧게 잡는다. 댓글은 스레드에서 다른 댓글들과 함께
 * 읽히는 것이라, 한 줄이 화면을 다 먹으면 스레드가 아니게 된다.
 */
public record CommentRequest(
        @NotBlank(message = "댓글을 적어 주세요.")
        @Size(max = MAX_BODY_LENGTH, message = "댓글은 " + MAX_BODY_LENGTH + "자를 넘을 수 없습니다.")
        String body) {

    /** 댓글 본문의 최대 글자 수. */
    public static final int MAX_BODY_LENGTH = 1000;
}
