package com.heattrip.heat_trip_backend.social.dto;

/**
 * 카드 댓글 응답 DTO.
 *
 * @param handle    표시 이름. null이면 프론트에서 "익명"으로 렌더링.
 * @param body      댓글 본문.
 * @param createdAt ISO-8601 문자열.
 */
public record CommentDto(
        Long id,
        String handle,
        String body,
        String createdAt
) {}
