package com.heattrip.heat_trip_backend.community.dto;

import com.heattrip.heat_trip_backend.community.entity.Comment;

import java.time.Instant;

/**
 * 댓글 하나 — 계약의 {@code Comment}. {@code required} 는 {@code [id, author, body, createdAt]}. *
 * <h2>{@code createdAt} 은 {@code Instant} 다 — {@code LocalDateTime} 이 아니다</h2>
 * <p>Jackson 이 {@code LocalDateTime} 을 <b>오프셋 없이</b> 직렬화한다
 * ({@code "2026-09-03T00:25:33.92"}). 계약은 {@code format: date-time} 이라고 선언해 뒀는데
 * 그건 오프셋이 있어야 성립하는 형식이고, 앱의 {@code DateTime.tryParse} 는 오프셋 없는
 * 문자열을 <b>기기 지역 시각</b>으로 읽는다 — 서버와 기기의 시간대가 다르면 그 차이만큼
 * 어긋난 시각이 그려진다. {@code WalkResponse} 가 같은 이유로 {@code Instant} 다.
 *
 * <p>2026-09 이전 계약의 {@code Comment.author} 에는 <b>사용자 식별자가 아예 없었다</b>.
 * {@code {nickname}} 뿐이라 "내 댓글인가" 판별·프로필 이동·차단이 계약상 불가능했다
 * (ADR-0017 규약 5가 {@link PersonRefResponse} 로 고쳤다).
 *
 * <h2>{@code hiddenByBlock} 은 읽는 사람마다 다른 값이다</h2>
 * <p>읽는 사람이 이 작성자를 가렸는가(#166). 목록에서 빼지 않는 이유는
 * {@link PostResponse} javadoc 과 같다 — 접는 것은 화면의 일이다.
 */
public record CommentResponse(
        long id,
        PersonRefResponse author,
        String body,
        Instant createdAt,
        boolean hiddenByBlock) {

    /** 가리기와 무관한 자리 — 방금 내가 쓴 댓글이다. */
    public static CommentResponse of(Comment comment) {
        return of(comment, false);
    }

    public static CommentResponse of(Comment comment, boolean hiddenByBlock) {
        return new CommentResponse(
                comment.getId(),
                PersonRefResponse.of(comment.getUser()),
                comment.getBody(),
                comment.createdAtInstant(),
                hiddenByBlock);
    }
}
