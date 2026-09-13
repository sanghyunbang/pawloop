package com.heattrip.heat_trip_backend.community.dto;

import com.heattrip.heat_trip_backend.community.entity.Post;

import java.time.Instant;
import java.util.List;

/**
 * 글 하나 — 계약의 {@code Post}.
 *
 * <p>계약의 {@code required} 는 {@code [id, author, board, title, body, commentCount,
 * reactions, createdAt, media]} 다. {@code loc}·{@code contentId} 만 {@code null} 이 될 수 있다. *
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
 *
 * <h2>{@code media} 는 항상 있다 — 비어 있을 수 있을 뿐 (#429)</h2>
 * <p>사진 없는 글은 {@code []} 다. {@code null} 을 안 쓰는 이유는 앱이 "없다" 와 "안 왔다" 를
 * 가를 이유가 없어서다. 순서는 올린 순서다. 영상이면 {@code posterUrl} 이 썸네일이고
 * {@code url} 이 재생할 파일이다.
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
        PostCourse course,

        /**
         * 글쓴이의 동네 — <b>구까지만</b> (#342). 안 골랐으면 {@code null} 이다.
         *
         * <p>동 이름을 안 싣는 것이 이 필드의 요점이다. 남의 사는 곳을 구보다 좁히면
         * 그것만으로 사람을 찾아갈 수 있다.
         */
        String authorDistrict,

        /** 붙은 사진·영상 (#429). 올린 순서. 없으면 빈 목록이다. */
        List<PostMedia> media) {

    /**
     * 카드에 그릴 만큼의 코스. 선은 <b>이미 잘라 낸 것을 더 줄인 것</b>(최대 40점)이라
     * 온전한 선이 필요하면 {@code GET /api/courses/&#123;id&#125;} 를 부른다.
     */
    public record PostCourse(long id, String name, int distanceM, List<List<Double>> path) {
    }

    /**
     * 카드에 그릴 만큼의 미디어 — 계약의 {@code PostMedia}.
     *
     * @param kind       {@code image} 또는 {@code video}
     * @param posterUrl  영상의 썸네일. 사진은 {@code null}
     * @param width      픽셀 폭. 앱이 올릴 때 준 값이라 없을 수 있다 — 없으면 화면이 정사각형 자리를 잡는다
     * @param durationMs 영상 길이. 사진은 {@code null}
     */
    public record PostMedia(long id, String kind, String url, String posterUrl,
                            Integer width, Integer height, Integer durationMs) {
    }

    /** 가리기와 무관한 자리 — 방금 내가 쓰거나 고친 글이다. */
    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions,
                                  List<PostMedia> media) {
        return of(post, commentCount, reactions, false, null, null, media);
    }

    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions,
                                  boolean hiddenByBlock, List<PostMedia> media) {
        return of(post, commentCount, reactions, hiddenByBlock, null, null, media);
    }

    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions,
                                  boolean hiddenByBlock, PostCourse course, List<PostMedia> media) {
        return of(post, commentCount, reactions, hiddenByBlock, course, null, media);
    }

    /**
     * @param authorDistrict 글쓴이의 시군구 이름. 서비스가 {@code NeighborhoodCatalog} 로
     *                       찾아 넣는다 — 사용자가 보낸 문자열이 아니다(#342).
     * @param media          붙은 사진·영상. {@code null} 이면 빈 목록으로 나간다
     */
    public static PostResponse of(Post post, int commentCount, ReactionSummaryResponse reactions,
                                  boolean hiddenByBlock, PostCourse course, String authorDistrict,
                                  List<PostMedia> media) {
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
                course,
                authorDistrict,
                media == null ? List.of() : List.copyOf(media));
    }
}
