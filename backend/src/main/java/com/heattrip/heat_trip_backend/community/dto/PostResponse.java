package com.heattrip.heat_trip_backend.community.dto;

import com.heattrip.heat_trip_backend.community.entity.Post;

import java.time.Instant;

/**
 * 글 하나 — 계약의 {@code Post}.
 *
 * <p>계약의 {@code required} 는 {@code [id, author, board, title, body, commentCount,
 * reactions, createdAt]} 이다. {@code loc}·{@code contentId} 만 {@code null} 이 될 수 있다. *
 * <h2>{@code createdAt} 은 {@code Instant} 다 — {@code LocalDateTime} 이 아니다</h2>
 * <p>Jackson 이 {@code LocalDateTime} 을 <b>오프셋 없이</b> 직렬화한다
 * ({@code "2026-09-03T00:25:33.92"}). 계약은 {@code format: date-time} 이라고 선언해 뒀는데
 * 그건 오프셋이 있어야 성립하는 형식이고, 앱의 {@code DateTime.tryParse} 는 오프셋 없는
 * 문자열을 <b>기기 지역 시각</b>으로 읽는다 — 서버와 기기의 시간대가 다르면 그 차이만큼
 * 어긋난 시각이 그려진다. {@code WalkResponse} 가 같은 이유로 {@code Instant} 다.
 *
 * <p><b>{@code handle} 을 싣지 않는다.</b> 그것은 작성 시점 스냅샷이고 표시는 현재값이다 —
 * {@link PersonRefResponse} javadoc 참조.
 *
 * <h2>{@code hiddenByBlock} 은 <b>읽는 사람마다 다른 값</b>이다</h2>
 * <p>읽는 사람이 이 작성자를 가렸는가(#166). <b>목록에서 빼지 않는 이유</b>는 채팅과 같다 —
 * 빼면 커서가 그 글을 건너뛰어 페이지 경계가 어긋나고, 가린 자리에 "보기" 를 두려면 본문이
 * 이미 와 있어야 한다. 접는 것은 화면의 일이다({@code ChatMessageResponse} 와 같은 규약).
 *
 * <p>게스트에게는 항상 {@code false} 다 — 가린 사람이 없다.
 *
 * <h2>{@code updatedAt} 은 {@code null} 일 수 있다</h2>
 * <p><b>{@code null} 이 "한 번도 안 고쳤다" 이다</b>(#211). {@code createdAt} 을 복사해 채우지
 * 않는다 — 그러면 화면이 모든 글에 '수정됨' 을 붙인다. {@code Comment} 에는 없다. 댓글 수정
 * 경로가 계약에 없어서다.
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
        Instant createdAt,
        Instant updatedAt,
        boolean hiddenByBlock,

        /**
         * 붙어 있는 코스 (#339). 안 붙였거나, 붙은 뒤 <b>비공개로 되돌렸거나</b>, 코스가
         * 지워졌으면 {@code null} 이다 — 그 셋을 구분하지 않는다. 화면에는 "그림이 없다" 로
         * 같기 때문이다.
         */
        PostCourse course) {

    /**
     * 카드에 그릴 만큼의 코스. 선은 <b>이미 잘라 낸 것을 더 줄인 것</b>(최대 40점)이라
     * 온전한 선이 필요하면 {@code GET /api/courses/&#123;id&#125;} 를 부른다.
     */
    public record PostCourse(long id, String name, int distanceM, java.util.List<java.util.List<Double>> path) {
    }

    /** 가리기와 무관한 자리 — 방금 내가 쓰거나 고친 글이다. */
    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions) {
        return of(post, commentCount, reactions, false, null);
    }

    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions,
                                  boolean hiddenByBlock) {
        return of(post, commentCount, reactions, hiddenByBlock, null);
    }

    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions,
                                  boolean hiddenByBlock, PostCourse course) {
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
                post.createdAtInstant(),
                post.updatedAtInstant(),
                hiddenByBlock,
                course);
    }
}
