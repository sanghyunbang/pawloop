package com.heattrip.heat_trip_backend.community.service;

import com.heattrip.heat_trip_backend.community.CommunityTime;
import com.heattrip.heat_trip_backend.community.dto.BookmarkStateResponse;
import com.heattrip.heat_trip_backend.community.dto.CommentPageResponse;
import com.heattrip.heat_trip_backend.community.dto.CommentRequest;
import com.heattrip.heat_trip_backend.community.dto.CommentResponse;
import com.heattrip.heat_trip_backend.community.dto.PostPageResponse;
import com.heattrip.heat_trip_backend.community.dto.PostPatchRequest;
import com.heattrip.heat_trip_backend.community.dto.PostRequest;
import com.heattrip.heat_trip_backend.community.dto.PostResponse;
import com.heattrip.heat_trip_backend.community.dto.ReactionSummaryResponse;
import com.heattrip.heat_trip_backend.community.entity.Comment;
import com.heattrip.heat_trip_backend.dog.DogOwnership;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.community.entity.Post;
import com.heattrip.heat_trip_backend.community.entity.PostBookmark;
import com.heattrip.heat_trip_backend.walk.CourseAttachment;
import com.heattrip.heat_trip_backend.S3.MediaAttachment;
import com.heattrip.heat_trip_backend.community.entity.Reaction;
import com.heattrip.heat_trip_backend.community.repository.CommentRepository;
import com.heattrip.heat_trip_backend.community.repository.PostBookmarkRepository;
import com.heattrip.heat_trip_backend.community.repository.PostRepository;
import com.heattrip.heat_trip_backend.moderation.Blocks;
import com.heattrip.heat_trip_backend.moderation.ReportReason;
import com.heattrip.heat_trip_backend.moderation.ReportReceipt;
import com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;
import com.heattrip.heat_trip_backend.community.repository.ReactionRepository;
import com.heattrip.heat_trip_backend.user.NeighborhoodCatalog;
import com.heattrip.heat_trip_backend.user.ViewerNeighborhood;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 커뮤니티 — 글·댓글·반응. 이슈 #170, ADR-0016·ADR-0017.
 *
 * <h2>목록의 쿼리 예산은 셋이다</h2>
 * <pre>
 *   1  글 한 장             (작성자를 left join fetch — 안 당기면 글마다 한 번씩 N+1)
 *   2  그 글들의 반응 전부     (집계와 mine 을 같은 결과에서 만든다)
 *   3  그 글들의 댓글 수       (group by 한 번)
 * </pre>
 *
 * <p><b>{@code social} 은 넷인데 여기는 셋이다.</b> 넷째가 "탈퇴자 조회" 인데, {@code social}
 * 은 {@code user_id} 를 FK 없는 스칼라로 들어서 "이 id 가 아직 있는가" 를 따로 물어야 한다.
 * 커뮤니티는 진짜 FK({@code ON DELETE SET NULL})라 <b>{@code null} 인 것이 곧 탈퇴</b>다 —
 * 그 질문의 답을 DB 가 이미 갖고 있다(#222).
 *
 * <h2>{@code board}·{@code type} 검증이 여기서만 난다</h2>
 * <p><b>이 클래스가 첫 방어선이고 유일한 방어선은 아니다.</b> 목록을 메시지에 실어 던진다 —
 * 그냥 "잘못된 값" 이라고만 하면 부르는 쪽이 계약을 다시 열어 봐야 한다. 여기가 사람에게
 * 말해 주는 자리다.
 *
 * <p>뒤에 DB 의 {@code CHECK} 가 있다({@code chk_post_board} · {@code chk_reaction_type},
 * {@code 14_community.sql} §B-5). #169 는 안 걸었는데 #167 이 걸었다 — 이 서비스를 안 지나는
 * 길(배치·수동 INSERT·다음 사람이 만들 관리 화면)이 있고, 그 길로 들어온 값은 목록 쿼리에는
 * 걸리는데 앱이 라벨을 못 찾아 빈 칸으로 뜬다(📌 #86 원칙 5).
 */
@Service
@Transactional(readOnly = true)
public class CommunityService {

    /** 계약의 {@code Board} enum. ASCII 키이고 화면 문구는 앱이 든다(ADR-0016). */
    static final Set<String> BOARDS = Set.of("walk_review", "pet_place", "health", "free", "brag");

    /** 계약의 {@code ReactionType} enum. */
    static final Set<String> REACTION_TYPES = Set.of("help", "cute", "empathy");

    /** 목록 한 장의 기본·최대 크기. 계약이 선언한 값이다. */
    private static final int DEFAULT_LIMIT = 20;
    private static final int MAX_LIMIT = 100;

    private final PostRepository posts;

    /** 코스는 walk 모듈의 표면 하나로만 만난다 — 엔티티를 들여다보지 않는다(#339). */
    private final CourseAttachment courses;
    private final CommentRepository comments;
    private final ReactionRepository reactions;

    /** 글 저장 (#451 4번). 반응과 같은 모양의 멱등 켜기·끄기. */
    private final PostBookmarkRepository bookmarks;

    /** 글에 찍힌 아이 (#451 5번) — 내 아이인지는 dog 모듈이 판정한다. 모듈 뿌리의 공개 타입만 든다. */
    private final DogOwnership dogs;

    /**
     * 신고 접수 — {@code moderation} 모듈의 공개 표면이다(#166).
     *
     * <p>화살표가 {@code community → moderation} 한 방향이다. 반대로 가면 순환이고, 그때
     * 잡히는 것이 이 문장이 아니라 {@code ModuleCycleTest} 여야 한다 — 그쪽 패키지에
     * {@code allowedDependencies = {}} 를 붙여 뒀다.
     */
    private final Reports reports;

    /**
     * 가리기 — {@code moderation} 모듈의 공개 표면이다(#166).
     *
     * <p>가린 사람의 글을 <b>목록에서 빼지 않는다.</b> 빼면 커서가 그 글을 건너뛰어 페이지
     * 경계가 어긋나고, 가린 자리에 "보기" 를 두려면 본문이 이미 와 있어야 한다. 접는 것은
     * 화면의 일이다 — {@code ChatBlocks} javadoc 이 채팅에서 같은 판단을 적어 뒀다.
     */
    private final Blocks blocks;

    /**
     * 글쓴이의 동네 코드에 이름을 붙이는 표 (#342). 사용자 모듈의 공개 면이다 —
     * 이 서비스는 이미 {@code Post.user} 로 그 모듈에 닿아 있다.
     */
    private final NeighborhoodCatalog neighborhoods;

    /** 보는 사람이 고른 동네를 묻는 자리 (#342). 사용자 모듈의 공개 면이다. */
    private final ViewerNeighborhood viewerNeighborhood;

    /**
     * 글에 붙는 사진·영상 — {@code S3} 모듈의 공개 표면이다(#429).
     *
     * <p>화살표가 {@code community → S3} 한 방향이다. {@code S3.media.MediaService} 를 직접
     * 부르면 하위 패키지라 기준선 96 이 는다 — {@code walk.CourseAttachment} 와 같은 모양으로
     * 루트의 인터페이스만 본다.
     */
    private final MediaAttachment media;

    public CommunityService(PostRepository posts, CommentRepository comments,
                            ReactionRepository reactions, Reports reports, Blocks blocks,
                            CourseAttachment courses, NeighborhoodCatalog neighborhoods,
                            ViewerNeighborhood viewerNeighborhood, MediaAttachment media,
                            PostBookmarkRepository bookmarks, DogOwnership dogs) {
        this.media = media;
        this.bookmarks = bookmarks;
        this.dogs = dogs;
        this.posts = posts;
        this.comments = comments;
        this.reactions = reactions;
        this.reports = reports;
        this.blocks = blocks;
        this.courses = courses;
        this.neighborhoods = neighborhoods;
        this.viewerNeighborhood = viewerNeighborhood;
    }

    // ─────────────────────────── 글 ───────────────────────────

    /**
     * 글 목록 한 장.
     *
     * @param viewerId 보는 사람. {@code null} 이면 <b>게스트</b>이고 {@code mine} 은 {@code null} 이다
     */
    public PostPageResponse page(Long viewerId, String board, String cursor, Integer limit) {
        return page(viewerId, board, cursor, limit, (String) null, null);
    }

    /**
     * 글 목록 — {@code neighborhood} 파라미터를 해석해서 (#342).
     *
     * <p>지금 받는 값은 {@code mine} 하나다. <b>구 코드를 직접 받지 않는다</b> — 받으면
     * 아무 구나 골라 훑을 수 있고, 그건 "우리 동네" 가 아니라 남의 동네 구경이다.
     *
     * <p>동네를 안 골랐거나 로그인 안 한 사람이 {@code mine} 을 부르면 <b>400</b> 이다.
     * 조용히 전국을 주면 화면은 "우리 동네" 라고 적힌 채 전국 글을 보여 준다.
     */
    public PostPageResponse pageForNeighborhood(Long viewerId, String board, String cursor,
                                                Integer limit, String neighborhood, Long dogId) {
        if (neighborhood == null || neighborhood.isBlank()) {
            return page(viewerId, board, cursor, limit, (String) null, dogId);
        }
        if (!"mine".equals(neighborhood)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "neighborhood 는 mine 만 받습니다.");
        }
        if (viewerId == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "로그인하고 동네를 고르면 우리 동네 글을 볼 수 있습니다.");
        }
        String sgg = viewerNeighborhood.sggOf(viewerId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST,
                        "동네를 먼저 골라 주세요."));
        return page(viewerId, board, cursor, limit, sgg, dogId);
    }

    /**
     * 글 목록 한 장 — <b>동네로 좁혀서</b> (#342).
     *
     * @param sggPrefix 시군구 앞 다섯 자리. {@code null} 이면 전국이다. 이 값은 컨트롤러가
     *                  <b>보는 사람의 저장된 동네</b>에서 뽑는다 — 쿼리로 받지 않는다.
     *                  받으면 아무 구나 골라 훑을 수 있고, 그건 "우리 동네" 가 아니라
     *                  남의 동네 구경이다
     */
    /**
     * @param dogId 찍힌 아이로 좁힌다(#451 5번, 아이 사진첩). {@code null} 이면 전부. 글은 공개라 남의
     *              아이 id 를 넣어도 400 이 아니다 — 그 아이의 글이 있으면 보인다.
     */
    public PostPageResponse page(Long viewerId, String board, String cursor, Integer limit,
                                 String sggPrefix, Long dogId) {
        String filter = normalizeBoardFilter(board);
        int size = clamp(limit);

        // 한 줄 더 읽어 hasMore 를 정한다. 별도 count 쿼리는 다음 장을 여는 사이에 값이
        // 바뀌고, 두 번 읽는 비용이 한 줄 더 읽는 비용보다 크다.
        Limit fetch = Limit.of(size + 1);
        List<Post> rows = CommunityCursor.parse(cursor)
                .map(c -> posts.findPageAfter(filter, sggPrefix, dogId, c.createdAt(), c.id(), fetch))
                .orElseGet(() -> posts.findPage(filter, sggPrefix, dogId, fetch));

        boolean hasMore = rows.size() > size;
        if (hasMore) {
            rows = rows.subList(0, size);
        }
        if (rows.isEmpty()) {
            return new PostPageResponse(List.of(), null, false);
        }

        List<PostResponse> items = itemsOf(rows, viewerId);

        Post last = rows.get(rows.size() - 1);
        String next = hasMore ? CommunityCursor.of(last.getCreatedAt(), last.getId()) : null;
        return new PostPageResponse(items, next, hasMore);
    }

    /** 글 상세. 없으면 404 다. */
    public PostResponse detail(Long viewerId, long postId) {
        Post post = posts.findDetail(postId).orElseThrow(CommunityService::notFound);
        return PostResponse.of(post,
                countComments(List.of(postId)).getOrDefault(postId, 0),
                summarizeOne(postId, viewerId),
                isBlocked(blockedBy(viewerId), post.getUser()),
                toPostCourse(cardOf(post, cardsFor(List.of(post)))),
                districtOf(post),
                mediaOf(post),
                isBookmarked(postId, viewerId),
                dogOf(post));
    }

    /**
     * 목록 한 장의 항목들. 글마다 묻지 않고 <b>관심사마다 한 번씩</b> 묻는다 — 반응 · 댓글 수 ·
     * 가리기 · 코스 · 사진 · 저장. 글마다 물으면 20건 조회에 쿼리가 백 개를 넘는다.
     */
    private List<PostResponse> itemsOf(List<Post> rows, Long viewerId) {
        List<Long> ids = rows.stream().map(Post::getId).toList();
        Map<Long, ReactionSummaryResponse> reactionsById = summarize(ids, viewerId);
        Map<Long, Integer> commentCounts = countComments(ids);

        // 한 장에 한 번 묻는다. 글마다 "가렸나" 를 물으면 20건 조회에 쿼리가 21개다 —
        // ChatMessages 가 같은 함정을 이미 피해 뒀다.
        Set<Long> blocked = blockedBy(viewerId);

        // 붙은 코스도 한 장에 한 번 묻는다 — 글마다 물으면 20건 조회에 쿼리가 21개다(#339).
        Map<Long, CourseAttachment.AttachedCourse> courseCards = cardsFor(rows);

        // 붙은 사진·영상도 한 장에 한 번 묻는다 (#429). 코스와 같은 이유다.
        Map<Long, List<PostResponse.PostMedia>> mediaByPost = mediaFor(rows);

        // 저장해 둔 글도 한 장에 한 번 (#451 4번). 게스트는 빈 집합이다.
        Set<Long> bookmarked = bookmarkedIn(ids, viewerId);

        List<PostResponse> items = new ArrayList<>(rows.size());
        for (Post p : rows) {
            items.add(PostResponse.of(p,
                    commentCounts.getOrDefault(p.getId(), 0),
                    reactionsById.getOrDefault(p.getId(), emptySummary(viewerId)),
                    isBlocked(blocked, p.getUser()),
                    toPostCourse(cardOf(p, courseCards)),
                    districtOf(p),
                    mediaByPost.getOrDefault(p.getId(), List.of()),
                    bookmarked.contains(p.getId()),
                    dogOf(p)));
        }
        return items;
    }

    @Transactional
    public PostResponse create(User me, PostRequest request) {
        requireBoard(request.board());
        Post saved = posts.save(Post.builder()
                .user(me)
                .board(request.board())
                .title(request.title())
                .body(request.body())
                .loc(blankToNull(request.loc()))
                .contentId(blankToNull(request.contentId()))
                // 작성 시점 스냅샷. 응답에는 안 싣는다 — users 행이 사라진 뒤 그 글을 누가
                // 썼는지 아는 유일한 기록이다(PersonRefResponse javadoc).
                .handle(displayNameOf(me))
                .courseId(request.courseId() == null ? null : requireAttachable(request.courseId(), me).id())
                // 찍힌 아이 — 내 아이만 (#451 5번). 남의 아이 id 는 400 이다.
                .dog(request.dogId() == null ? null : requireOurDog(me, request.dogId()))
                .build());
        // 업로드가 먼저고 글이 나중이다 (#429). 붙일 수 없는 것이 하나라도 있으면 여기서 던지고,
        // 같은 트랜잭션이라 방금 저장한 글도 함께 되돌아간다 — 사진 없는 글이 조용히 남지 않는다.
        List<PostResponse.PostMedia> attached = toPostMedia(media.attach(
                MediaAttachment.REF_POST, String.valueOf(saved.getId()),
                request.mediaIds() == null ? List.of() : request.mediaIds(), me.getId()));
        return PostResponse.of(saved, 0, emptySummary(me.getId()), false,
                toPostCourse(cardOf(saved, cardsFor(List.of(saved)))),
                districtOf(saved),
                attached,
                false,
                dogOf(saved));
    }

    /**
     * 글쓴이의 시군구 이름 — <b>구까지만</b> (#342).
     *
     * <p>이름은 서버의 표에서만 나온다. 사용자가 보낸 문자열을 쓰면 아무나 자기 동네를
     * "청와대" 라고 적어 남의 화면에 띄울 수 있다. 동네를 안 골랐거나 모르는 코드면
     * {@code null} 이고, 화면은 그 자리를 비운다.
     */
    private String districtOf(Post post) {
        User author = post.getUser();
        if (author == null) return null;
        return neighborhoods.find(author.getNeighborhoodCode())
                .map(NeighborhoodCatalog.Sigungu::name)
                .orElse(null);
    }

    // ─────────────────────────── 댓글 ───────────────────────────

    public CommentPageResponse comments(Long viewerId, long postId, String cursor, Integer limit) {
        requirePost(postId);
        int size = clamp(limit);
        Limit fetch = Limit.of(size + 1);

        List<Comment> rows = CommunityCursor.parse(cursor)
                .map(c -> comments.findPageAfter(postId, c.createdAt(), c.id(), fetch))
                .orElseGet(() -> comments.findPage(postId, fetch));

        boolean hasMore = rows.size() > size;
        if (hasMore) {
            rows = rows.subList(0, size);
        }
        if (rows.isEmpty()) {
            return new CommentPageResponse(List.of(), null, false);
        }

        Set<Long> blocked = blockedBy(viewerId);
        Comment last = rows.get(rows.size() - 1);
        return new CommentPageResponse(
                rows.stream()
                        .map(c -> CommentResponse.of(c, isBlocked(blocked, c.getUser())))
                        .toList(),
                hasMore ? CommunityCursor.of(last.getCreatedAt(), last.getId()) : null,
                hasMore);
    }

    @Transactional
    public CommentResponse addComment(User me, long postId, CommentRequest request) {
        Post post = requirePost(postId);
        Comment saved = comments.save(Comment.builder()
                .post(post)
                .user(me)
                .body(request.body())
                .handle(displayNameOf(me))
                .build());
        return CommentResponse.of(saved);
    }

    // ─────────────────────────── 신고 ───────────────────────────

    /**
     * 글을 신고한다 — 이슈 #166.
     *
     * <h2>신고 시점 사본을 함께 넘긴다</h2>
     * <p>{@code moderation} 은 아무 도메인도 안 부르므로, 무엇을 신고했는지는 여기서 읽어
     * 값으로 넘긴다. <b>원본이 지워진 뒤에 읽는 기록</b>이라 제목·본문·작성자까지 벤다.
     *
     * <h2>내 글은 못 신고한다</h2>
     * <p>채팅 신고가 같은 규칙이다({@code REPORT_SELF}). 자기 글을 신고하는 것은 실수이거나
     * 신고 수를 부풀리는 것이고, 둘 다 운영자가 세는 숫자를 흐린다.
     *
     * <h2>중복을 막지 않는다</h2>
     * <p>같은 글을 여러 번 신고할 수 있다. <b>글이 수정되기 때문이다</b>(#211) — 막으면
     * 작성자가 신고 뒤 본문을 더 나쁜 것으로 고쳤을 때 재신고가 안 된다. 도배는
     * 레이트리밋({@code report} 버킷 분당 10)이 막는다.
     */
    @Transactional
    public ReportReceipt reportPost(User me, long postId, String reason, String memo) {
        Post post = requirePost(postId);
        requireNotMine(post.getUser(), me.getId());

        return reports.file(
                me.getId(),
                post.getUser() == null ? null : post.getUser().getId(),
                requireReason(reason),
                memo,
                // 좌표가 사본에 붙는다 — 부모는 "누가·누구를·왜·언제" 만 든다 (#254).
                List.of(snapshotOf(post, ReportSnapshotInput.Role.TARGET)));
    }

    /**
     * 댓글을 신고한다 — 이슈 #166.
     *
     * <p><b>부모 글을 맥락으로 함께 벤다.</b> 댓글 한 줄만 남으면 운영자가 무슨 글에 달린
     * 말인지 모르고, 글을 지우면 {@code fk_comment_post} 가 CASCADE 라 댓글이 함께 사라져
     * 되짚을 수도 없다.
     */
    @Transactional
    public ReportReceipt reportComment(User me, long postId, long commentId,
                                       String reason, String memo) {
        Post post = requirePost(postId);
        Comment comment = comments.findById(commentId)
                .filter(c -> c.getPost().getId() == postId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "댓글을 찾을 수 없습니다."));
        requireNotMine(comment.getUser(), me.getId());

        return reports.file(
                me.getId(),
                comment.getUser() == null ? null : comment.getUser().getId(),
                requireReason(reason),
                memo,
                // 부모 글은 맥락이고, 그 줄도 자기 좌표를 든다 — 글이 지워진 뒤에도
                // "어느 글에 달린 댓글이었나" 를 말할 수 있어야 한다 (#254).
                List.of(snapshotOf(comment), snapshotOf(post, ReportSnapshotInput.Role.CONTEXT)));
    }

    private static ReportSnapshotInput snapshotOf(Post post, ReportSnapshotInput.Role role) {
        return new ReportSnapshotInput(
                role,
                ReportTarget.post(post.getId()),
                null, // 커뮤니티에는 순번이 없다 — 채팅의 room_seq 자리다
                post.getUser() == null ? null : post.getUser().getId(),
                post.getHandle(),
                post.getTitle(),
                post.getBody(),
                null, // 종류도 채팅 것이다
                post.createdAtInstant());
    }

    private static ReportSnapshotInput snapshotOf(Comment comment) {
        return ReportSnapshotInput.target(
                ReportTarget.comment(comment.getId()),
                comment.getUser() == null ? null : comment.getUser().getId(),
                comment.getHandle(),
                null, // 댓글에는 제목이 없다
                comment.getBody(),
                comment.createdAtInstant());
    }

    /**
     * 내 것이면 400 이다.
     *
     * <p><b>탈퇴한 사람의 글은 신고할 수 있다.</b> {@code user} 가 {@code null} 이어도 글은
     * 남아 있고, 그 글이 문제라는 사실은 작성자가 떠난 것과 무관하다.
     */
    private static void requireNotMine(User author, long meId) {
        if (author != null && author.getId().equals(meId)) {
            throw new IllegalArgumentException("내가 쓴 것은 신고할 수 없습니다.");
        }
    }

    /**
     * 계약의 {@code ReportReason} 으로 읽는다.
     *
     * <p><b>모르는 값을 {@code other} 로 눕히지 않는다.</b> 그러면 앱의 오타가 조용히
     * 통과해서 운영자가 세는 숫자가 소리 없이 틀어진다 — 채팅 신고가 같은 판단을 했다.
     */
    private static ReportReason requireReason(String reason) {
        return ReportReason.fromWire(reason).orElseThrow(() -> new IllegalArgumentException(
                "신고 사유가 올바르지 않습니다. 가능한 값: " + sortedReasons()));
    }

    private static String sortedReasons() {
        return java.util.Arrays.stream(ReportReason.values())
                .map(ReportReason::wireValue)
                .sorted()
                .collect(java.util.stream.Collectors.joining(", "));
    }

    // ─────────────────────────── 반응 ───────────────────────────

    /**
     * 글을 지운다 — 이슈 #211.
     *
     * <h2>댓글과 반응이 함께 사라진다</h2>
     * <p>{@code fk_comment_post}·{@code fk_reaction_post} 가 {@code ON DELETE CASCADE} 다.
     * 그것이 {@code 14_community.sql} §D 가 적어 둔 결정이다 — <b>부모 없는 행을 남기지
     * 않는다.</b> 남으면 어느 목록에도 안 뜨면서 자리만 차지하고, 나중에 세면 댓글 수가
     * 맞지 않는데 왜 안 맞는지 아무도 모른다.
     *
     * <p>남의 댓글이 함께 사라지는 것은 의도다. 글이 없으면 그 댓글은 읽을 맥락이 없다.
     * {@code users} 로 가는 FK 가 {@code SET NULL} 인 것과는 다른 판단인데, 거기서는
     * <b>글이 남아 있고</b> 작성자만 사라지는 것이라 남의 댓글이 읽힐 자리가 있다.
     *
     * <h2>남의 글은 403 이다 — 404 가 아니다</h2>
     * <p>{@code Dogs}·{@code Walks} 는 404 로 합친다("남의 것과 없는 것이 구별되지 않는다",
     * ADR-0017 규약 3). 커뮤니티는 <b>반대다</b> — 글은 누구나 읽을 수 있어서 <b>존재가 이미
     * 공개</b>다. 404 로 숨겨도 방금 GET 으로 본 것을 숨기는 것이라 아무것도 못 가리고,
     * 대신 사용자가 "지웠는데 사라지지 않았다" 로 읽는다.
     *
     * @throws ResponseStatusException 404 — 그런 글이 없으면
     * @throws ResponseStatusException 403 — 내 글이 아니면
     */
    /**
     * 글을 고친다 — 이슈 #211. <b>내가 쓴 글만.</b>
     *
     * <p>{@code null} 인 필드는 안 바꾼다. 셋 다 없으면 {@code 400} 이다 — 아무 일도 안 하면서
     * 200 을 주면 그건 "고쳐졌다" 로 읽힌다(계약의 {@code minProperties: 1}).
     *
     * <p><b>실제로 바뀐 것이 없으면 {@code updatedAt} 을 안 건드린다.</b> 같은 값을 다시 보낸
     * 것만으로 '수정됨' 이 붙으면 그 표시가 읽는 사람에게 아무것도 말해 주지 않는다.
     * 판단은 {@link Post#edit} 안에 있다 — 무엇이 "바뀜" 인지는 엔티티가 안다.
     */
    @Transactional
    public PostResponse updatePost(User me, long postId, PostPatchRequest request) {
        if (request.isEmpty()) {
            throw new IllegalArgumentException("고칠 내용이 없습니다. board·title·body 중 하나는 보내야 합니다.");
        }
        if (request.hasBlank()) {
            throw new IllegalArgumentException("빈 값으로는 고칠 수 없습니다.");
        }
        if (request.board() != null) {
            requireBoard(request.board());
        }

        Post post = requirePost(postId);
        requireMine(post.getUser(), me.getId(), "글");
        post.edit(request.board(), request.title(), request.body());
        if (request.dogId() != null) {
            post.attachDog(requireOurDog(me, request.dogId()));
        }

        // 사진·영상은 키가 왔을 때만 통째로 갈아 끼운다 (#429). 안 왔으면 지금 것 그대로다.
        List<PostResponse.PostMedia> attached = request.mediaIds() == null
                ? mediaOf(post)
                : toPostMedia(media.replace(MediaAttachment.REF_POST, String.valueOf(postId),
                        request.mediaIds(), me.getId()));

        return PostResponse.of(post,
                countComments(List.of(postId)).getOrDefault(postId, 0),
                summarizeOne(postId, me.getId()),
                attached,
                isBookmarked(postId, me.getId()),
                dogOf(post));
    }

    /**
     * 글에 코스를 붙인다 (#339). 이미 붙어 있으면 갈아 끼운다.
     *
     * <p>붙일 수 있는 것은 <b>내 것이면서 공개된 코스</b>뿐이다({@link CourseAttachment}).
     * 비공개를 붙이면 남들에게 빈 자리로 보이므로, 서버가 몰래 공개로 바꾸지 않고 막는다.
     */
    @Transactional
    public PostResponse attachCourse(User me, long postId, long courseId) {
        Post post = requirePost(postId);
        requireMine(post.getUser(), me.getId(), "글");
        CourseAttachment.AttachedCourse card = requireAttachable(courseId, me);
        post.attachCourse(card.id());
        return PostResponse.of(post,
                countComments(List.of(postId)).getOrDefault(postId, 0),
                summarizeOne(postId, me.getId()),
                false,
                toPostCourse(card),
                mediaOf(post),
                isBookmarked(postId, me.getId()),
                dogOf(post));
    }

    /** 붙은 코스를 뗀다. 코스 자체는 그대로다 — 글에서 그림만 빠진다. */
    @Transactional
    public PostResponse detachCourse(User me, long postId) {
        Post post = requirePost(postId);
        requireMine(post.getUser(), me.getId(), "글");
        post.attachCourse(null);
        return PostResponse.of(post,
                countComments(List.of(postId)).getOrDefault(postId, 0),
                summarizeOne(postId, me.getId()),
                false,
                null,
                mediaOf(post),
                isBookmarked(postId, me.getId()),
                dogOf(post));
    }

    /**
     * 이 글들에 붙은 사진·영상 (#429). 글마다 물으면 20건 조회에 쿼리가 21개다 — 코스와 같은
     * 이유로 한 번에 묻는다. 없는 글은 키가 없으므로 부르는 쪽이 빈 목록으로 읽는다.
     */
    private Map<Long, List<PostResponse.PostMedia>> mediaFor(List<Post> rows) {
        if (rows.isEmpty()) {
            return Map.of();
        }
        List<String> refs = rows.stream().map(p -> String.valueOf(p.getId())).toList();
        Map<String, List<MediaAttachment.AttachedMedia>> attached =
                media.attachedTo(MediaAttachment.REF_POST, refs);
        Map<Long, List<PostResponse.PostMedia>> out = new java.util.HashMap<>();
        for (Post p : rows) {
            List<MediaAttachment.AttachedMedia> list = attached.get(String.valueOf(p.getId()));
            if (list != null && !list.isEmpty()) {
                out.put(p.getId(), toPostMedia(list));
            }
        }
        return out;
    }

    private List<PostResponse.PostMedia> mediaOf(Post post) {
        return mediaFor(List.of(post)).getOrDefault(post.getId(), List.of());
    }

    private static List<PostResponse.PostMedia> toPostMedia(List<MediaAttachment.AttachedMedia> list) {
        return list.stream()
                .map(m -> new PostResponse.PostMedia(m.id(), m.kind().wire(), m.url(), m.posterUrl(),
                        m.width(), m.height(), m.durationMs()))
                .toList();
    }

    private CourseAttachment.AttachedCourse requireAttachable(long courseId, User me) {
        return courses.forAttaching(courseId, me.getId())
                .orElseThrow(() -> new IllegalArgumentException(
                        "내 코스가 아니거나 비공개 코스입니다. 공개로 바꾼 뒤 붙일 수 있어요."));
    }

    /** 이 글들에 붙은 코스 카드. 공개된 것만 오고, 없는 것은 빠진다. */
    private Map<Long, CourseAttachment.AttachedCourse> cardsFor(List<Post> rows) {
        Set<Long> ids = new LinkedHashSet<>();
        for (Post p : rows) {
            if (p.getCourseId() != null) {
                ids.add(p.getCourseId());
            }
        }
        return ids.isEmpty() ? Map.of() : courses.cards(ids);
    }

    /**
     * 이 글에 붙은 카드. 붙은 것이 없으면 {@code null} 이다.
     *
     * <p>{@code map.get(post.getCourseId())} 를 바로 부르지 않는 이유: 붙은 코스가 없는 글은
     * 키가 {@code null} 인데 {@link Map#of()} 가 주는 불변 맵은 <b>null 키 조회에서 NPE</b> 다.
     * 코스 없는 글을 쓰는 순간 500 이 났다 — 테스트가 그것을 잡았다.
     */
    private static CourseAttachment.AttachedCourse cardOf(
            Post post, Map<Long, CourseAttachment.AttachedCourse> cards) {
        return post.getCourseId() == null ? null : cards.get(post.getCourseId());
    }

    private static PostResponse.PostCourse toPostCourse(CourseAttachment.AttachedCourse card) {
        return card == null
                ? null
                : new PostResponse.PostCourse(card.id(), card.name(), card.distanceM(), card.path());
    }

    @Transactional
    public void deletePost(User me, long postId) {
        Post post = requirePost(postId);
        requireMine(post.getUser(), me.getId(), "글");
        // 붙은 사진·영상은 글과 함께 사라진다 — 행도 S3 객체도 (#429). DB 의 CASCADE 로는 안
        // 된다: media_objects 는 post 로 나가는 FK 가 없고(ref_type/ref_id 는 불투명한 쌍),
        // 있어도 S3 의 파일은 DB 가 모른다.
        media.detachAll(MediaAttachment.REF_POST, String.valueOf(postId));
        posts.delete(post);
    }

    /**
     * 댓글을 지운다 — 이슈 #211.
     *
     * <p><b>글 주인이 남의 댓글을 지우지 못한다.</b> 그건 관리(moderation)이고 그 결정은
     * #166 이 갖고 있다. 여기서 미리 열면 신고·차단 모양이 정해질 때 두 벌이 된다.
     *
     * <p>글이 그 댓글의 것이 맞는지 함께 본다. {@code /posts/1/comments/2} 에서 2번 댓글이
     * 다른 글의 것이면 <b>404</b> 다 — 경로가 가리키는 것이 없다는 뜻이지 권한 문제가 아니다.
     */
    @Transactional
    public void deleteComment(User me, long postId, long commentId) {
        requirePost(postId);
        Comment comment = comments.findById(commentId)
                .filter(c -> c.getPost().getId() == postId)
                .orElseThrow(() -> new ResponseStatusException(
                        HttpStatus.NOT_FOUND, "댓글을 찾을 수 없습니다."));
        requireMine(comment.getUser(), me.getId(), "댓글");
        comments.delete(comment);
    }

    /**
     * 반응을 누른다. <b>멱등</b>이다 — 이미 눌러 뒀어도 200 이고 집계가 늘지 않는다.
     *
     * <p><b>동시 요청에서도 그렇다.</b> #170 은 {@code saveAndFlush} 뒤에
     * {@code DataIntegrityViolationException} 을 삼켰는데, 그건 멱등이 아니었다 — 제약 위반이
     * 나는 순간 Hibernate 가 트랜잭션을 rollback-only 로 표시하고 예외를 잡아도 그 표시가 안
     * 지워져서, 결국 500 이 나간다. 지금은 한 문장짜리
     * {@link ReactionRepository#insertIfAbsent}(중복 키만 no-op)가 그 창을 닫는다.
     */
    @Transactional
    public ReactionSummaryResponse addReaction(User me, long postId, String type) {
        requireReactionType(type);
        requirePost(postId);
        reactions.insertIfAbsent(postId, me.getId(), type, CommunityTime.nowUtc());
        return summarizeOne(postId, me.getId());
    }

    /**
     * 반응을 취소한다. <b>멱등</b>이다 — 안 눌렀던 것을 취소해도 200 이다.
     *
     * <p>조회 후 엔티티 삭제가 아니라 조건 삭제다. 동시에 두 번 취소하면 진 쪽의
     * {@code DELETE ... WHERE id = ?} 가 0행이 되고 Hibernate 가 {@code StaleStateException}
     * 으로 올린다 — 0행이 정상인 이 자리에서는 그게 500 이 된다.
     */
    @Transactional
    public ReactionSummaryResponse removeReaction(User me, long postId, String type) {
        requireReactionType(type);
        requirePost(postId);
        reactions.deleteIfPresent(postId, me.getId(), type);
        return summarizeOne(postId, me.getId());
    }

    // ─────────────────────────── 저장 (#451 4번) ───────────────────────────

    /**
     * 글을 저장한다. <b>멱등</b>이다 — 이미 저장해 뒀어도 200 이고 행이 안 는다. 반응과 같은
     * 한 문장짜리 삽입({@link PostBookmarkRepository#insertIfAbsent})이라 동시 요청에서도 그렇다.
     */
    @Transactional
    public BookmarkStateResponse bookmark(User me, long postId) {
        requirePost(postId);
        bookmarks.insertIfAbsent(postId, me.getId(), CommunityTime.nowUtc());
        return new BookmarkStateResponse(true);
    }

    /** 저장을 뺀다. <b>멱등</b>이다 — 안 저장했던 것을 빼도 200 이다. */
    @Transactional
    public BookmarkStateResponse unbookmark(User me, long postId) {
        requirePost(postId);
        bookmarks.deleteIfPresent(postId, me.getId());
        return new BookmarkStateResponse(false);
    }

    /**
     * 내가 저장한 글 — <b>저장한 순</b>이지 글이 쓰인 순이 아니다(Instagram 의 저장됨). 커서의 두
     * 축이 {@code post_bookmark.(created_at, id)} 인 이유다. 남의 목록은 물을 길이 없다 — 보는
     * 사람의 것만 묻는다.
     */
    public PostPageResponse bookmarks(User me, String cursor, Integer limit) {
        int size = clamp(limit);
        Limit fetch = Limit.of(size + 1);
        List<PostBookmark> rows = CommunityCursor.parse(cursor)
                .map(c -> bookmarks.findPageAfter(me.getId(), c.createdAt(), c.id(), fetch))
                .orElseGet(() -> bookmarks.findPage(me.getId(), fetch));

        boolean hasMore = rows.size() > size;
        if (hasMore) {
            rows = rows.subList(0, size);
        }
        if (rows.isEmpty()) {
            return new PostPageResponse(List.of(), null, false);
        }

        List<PostResponse> items = itemsOf(rows.stream().map(PostBookmark::getPost).toList(), me.getId());
        PostBookmark last = rows.get(rows.size() - 1);
        String next = hasMore ? CommunityCursor.of(last.getCreatedAt(), last.getId()) : null;
        return new PostPageResponse(items, next, hasMore);
    }

    // ─────────────────────────── 찍힌 아이 (#451 5번) ───────────────────────────

    /**
     * <b>우리 집</b> 아이여야 붙는다(#563). 남의 아이 id 는 400 — 404 로 가르면 남의 아이
     * id 를 훑을 수 있다.
     *
     * <p>집 기준인 이유는 아이를 고르는 화면이 집 아이를 보여 주기 때문이다. 화면이 고를 수
     * 있다고 해 놓고 저장에서 거절하면 그게 더 나쁜 실패다.
     */
    private Dog requireOurDog(User me, long dogId) {
        if (!dogs.householdDogIds(me.getId()).contains(dogId)) {
            throw new IllegalArgumentException("우리 집 아이만 글에 붙일 수 있습니다.");
        }
        return dogs.requireInHouseholdEntity(me.getId(), dogId);
    }

    /** 카드의 아이 꼬리표. 보낸 아이(소프트 삭제)는 안 그린다 — 이름만 남은 꼬리표는 헛갈린다. */
    private PostResponse.PostDog dogOf(Post post) {
        Dog dog = post.getDog();
        if (dog == null || dog.getDeletedAt() != null) {
            return null;
        }
        return new PostResponse.PostDog(dog.getId(), dog.getName(),
                dog.getAvatar() == null ? null : media.publicUrl(dog.getAvatar()));
    }

    /** 목록 한 장 중 내가 저장한 글의 id. 게스트는 빈 집합이다. */
    private Set<Long> bookmarkedIn(List<Long> postIds, Long viewerId) {
        if (viewerId == null || postIds.isEmpty()) {
            return Set.of();
        }
        return bookmarks.findPostIdsIn(viewerId, postIds);
    }

    private boolean isBookmarked(long postId, Long viewerId) {
        return bookmarkedIn(List.of(postId), viewerId).contains(postId);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 글들의 반응을 <b>한 번에</b> 모아 집계와 {@code mine} 을 같은 결과에서 만든다.
     *
     * <p>따로 물으면 쿼리가 둘이 되고, 그 사이에 값이 바뀌면 카운트와 {@code mine} 이 어긋난다 —
     * 사용자에게는 "눌렀는데 숫자가 안 올랐다" 로 보인다.
     */
    private Map<Long, ReactionSummaryResponse> summarize(List<Long> postIds, Long viewerId) {
        Map<Long, int[]> counts = new HashMap<>();
        Map<Long, List<String>> mine = new HashMap<>();

        for (Reaction r : reactions.findByPostIdIn(postIds)) {
            long postId = r.getPost().getId();
            int[] c = counts.computeIfAbsent(postId, k -> new int[3]);
            int slot = slotOf(r.getType());
            if (slot >= 0) {
                c[slot]++;
            }
            // 탈퇴한 사람의 반응은 user 가 null 이다 — 집계에는 들어가고 mine 에는 안 들어간다.
            if (viewerId != null && r.getUser() != null && viewerId.equals(r.getUser().getId())) {
                mine.computeIfAbsent(postId, k -> new ArrayList<>()).add(r.getType());
            }
        }

        Map<Long, ReactionSummaryResponse> out = new HashMap<>();
        for (Long id : postIds) {
            int[] c = counts.getOrDefault(id, new int[3]);
            out.put(id, ReactionSummaryResponse.of(c[0], c[1], c[2],
                    viewerId == null ? null : mine.getOrDefault(id, List.of())));
        }
        return out;
    }

    private ReactionSummaryResponse summarizeOne(long postId, Long viewerId) {
        return summarize(List.of(postId), viewerId).get(postId);
    }

    private Map<Long, Integer> countComments(List<Long> postIds) {
        Map<Long, Integer> out = new HashMap<>();
        for (Object[] row : comments.countByPostIdInGroupBy(postIds)) {
            out.put((Long) row[0], ((Number) row[1]).intValue());
        }
        return out;
    }

    /** 게스트는 {@code null}, 로그인했으면 빈 배열. 둘은 다른 뜻이다(ADR-0017 규약 6). */
    private static ReactionSummaryResponse emptySummary(Long viewerId) {
        return ReactionSummaryResponse.of(0, 0, 0, viewerId == null ? null : List.of());
    }

    private static int slotOf(String type) {
        return switch (type) {
            case "help" -> 0;
            case "cute" -> 1;
            case "empathy" -> 2;
            default -> -1;
        };
    }

    /**
     * 내가 쓴 것인가.
     *
     * <p><b>작성자가 {@code null} 이면 아무도 못 지운다.</b> 탈퇴한 사람의 글이다
     * ({@code ON DELETE SET NULL}, ADR-0016 결정 5). 그 글의 주인은 이제 없고, 아무나
     * 지울 수 있게 하면 그것이 곧 관리 권한이 된다 — 그건 #166 이 정할 일이다.
     */
    private static void requireMine(User owner, long meId, String what) {
        if (owner == null) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "지울 수 없는 " + what + "입니다.");
        }
        if (!owner.getId().equals(meId)) {
            throw new ResponseStatusException(
                    HttpStatus.FORBIDDEN, "내가 쓴 " + what + "만 지울 수 있습니다.");
        }
    }

    private Post requirePost(long postId) {
        return posts.findById(postId).orElseThrow(CommunityService::notFound);
    }

    private static ResponseStatusException notFound() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "글을 찾을 수 없습니다.");
    }

    private static void requireBoard(String board) {
        if (!BOARDS.contains(board)) {
            throw new IllegalArgumentException(
                    "게시판이 올바르지 않습니다. 가능한 값: " + sorted(BOARDS));
        }
    }

    private static void requireReactionType(String type) {
        if (!REACTION_TYPES.contains(type)) {
            throw new IllegalArgumentException(
                    "반응 종류가 올바르지 않습니다. 가능한 값: " + sorted(REACTION_TYPES));
        }
    }

    /** 메시지에 실을 목록. {@code Set} 의 순회 순서는 정해져 있지 않아 정렬해서 낸다. */
    private static String sorted(Set<String> values) {
        return String.join(", ", values.stream().sorted().toList());
    }

    /** 목록 필터. 빈 문자열은 "전체" 로 읽는다 — 앱이 칩을 껐을 때 빈 값을 보낸다. */
    private static String normalizeBoardFilter(String board) {
        String value = blankToNull(board);
        if (value != null && !BOARDS.contains(value)) {
            throw new IllegalArgumentException(
                    "게시판이 올바르지 않습니다. 가능한 값: " + sorted(BOARDS));
        }
        return value;
    }

    private static int clamp(Integer limit) {
        if (limit == null || limit <= 0) {
            return DEFAULT_LIMIT;
        }
        return Math.min(limit, MAX_LIMIT);
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    /** 저장할 스냅샷. 닉네임이 없으면 이름, 그것도 없으면 안 적는다. */
    /**
     * 이 사람이 가린 사람들 — 이슈 #166.
     *
     * <p><b>게스트에게는 빈 집합</b>이다. 가린 사람이 없으므로 아무것도 안 접힌다.
     *
     * <p>한 장에 한 번만 부른다. 글마다 물으면 20건 조회에 쿼리가 21개가 된다.
     */
    private Set<Long> blockedBy(Long viewerId) {
        return viewerId == null ? Set.of() : blocks.blockedBy(viewerId);
    }

    /**
     * 이 글·댓글을 접어야 하는가.
     *
     * <p><b>탈퇴한 작성자는 접지 않는다.</b> 가릴 대상이 이미 없고, 표시도 이미 '알 수 없음'
     * 이다.
     */
    private static boolean isBlocked(Set<Long> blocked, User author) {
        return author != null && blocked.contains(author.getId());
    }

    private static String displayNameOf(User user) {
        if (user.getNickname() != null && !user.getNickname().isBlank()) {
            return user.getNickname();
        }
        return blankToNull(user.getName());
    }
}
