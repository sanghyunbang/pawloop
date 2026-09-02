package com.heattrip.heat_trip_backend.community.dto;

import com.heattrip.heat_trip_backend.community.entity.Comment;

import java.time.LocalDateTime;

/**
 * 댓글 하나 — 계약의 {@code Comment}. {@code required} 는 {@code [id, author, body, createdAt]}.
 *
 * <p>2026-09 이전 계약의 {@code Comment.author} 에는 <b>사용자 식별자가 아예 없었다</b>.
 * {@code {nickname}} 뿐이라 "내 댓글인가" 판별·프로필 이동·차단이 계약상 불가능했다
 * (ADR-0017 규약 5가 {@link PersonRefResponse} 로 고쳤다).
 */
public record CommentResponse(
        long id,
        PersonRefResponse author,
        String body,
        LocalDateTime createdAt) {

    public static CommentResponse of(Comment comment) {
        return new CommentResponse(
                comment.getId(),
                PersonRefResponse.of(comment.getUser()),
                comment.getBody(),
                comment.getCreatedAt());
    }
}
