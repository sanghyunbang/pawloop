package com.heattrip.heat_trip_backend.community.dto;

import com.heattrip.heat_trip_backend.community.entity.Post;

import java.time.LocalDateTime;

/**
 * 글 하나 — 계약의 {@code Post}.
 *
 * <p>계약의 {@code required} 는 {@code [id, author, board, title, body, commentCount,
 * reactions, createdAt]} 이다. {@code loc}·{@code contentId} 만 {@code null} 이 될 수 있다.
 *
 * <p><b>{@code handle} 을 싣지 않는다.</b> 그것은 작성 시점 스냅샷이고 표시는 현재값이다 —
 * {@link PersonRefResponse} javadoc 참조.
 */
public record PostResponse(
        long id,
        PersonRefResponse author,
        String board,
        String loc,
        String contentId,
        String title,
        String body,
        int commentCount,
        ReactionSummaryResponse reactions,
        LocalDateTime createdAt) {

    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions) {
        return new PostResponse(
                post.getId(),
                PersonRefResponse.of(post.getUser()),
                post.getBoard(),
                post.getLoc(),
                post.getContentId(),
                post.getTitle(),
                post.getBody(),
                commentCount,
                reactions,
                post.getCreatedAt());
    }
}
