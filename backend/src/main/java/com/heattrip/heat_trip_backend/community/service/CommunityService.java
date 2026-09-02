package com.heattrip.heat_trip_backend.community.service;

import com.heattrip.heat_trip_backend.community.CommunityTime;
import com.heattrip.heat_trip_backend.community.dto.CommentPageResponse;
import com.heattrip.heat_trip_backend.community.dto.CommentRequest;
import com.heattrip.heat_trip_backend.community.dto.CommentResponse;
import com.heattrip.heat_trip_backend.community.dto.PostPageResponse;
import com.heattrip.heat_trip_backend.community.dto.PostRequest;
import com.heattrip.heat_trip_backend.community.dto.PostResponse;
import com.heattrip.heat_trip_backend.community.dto.ReactionSummaryResponse;
import com.heattrip.heat_trip_backend.community.entity.Comment;
import com.heattrip.heat_trip_backend.community.entity.Post;
import com.heattrip.heat_trip_backend.community.entity.Reaction;
import com.heattrip.heat_trip_backend.community.repository.CommentRepository;
import com.heattrip.heat_trip_backend.community.repository.PostRepository;
import com.heattrip.heat_trip_backend.community.repository.ReactionRepository;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.data.domain.Limit;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.ArrayList;
import java.util.HashMap;
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
    private final CommentRepository comments;
    private final ReactionRepository reactions;

    public CommunityService(PostRepository posts, CommentRepository comments, ReactionRepository reactions) {
        this.posts = posts;
        this.comments = comments;
        this.reactions = reactions;
    }

    // ─────────────────────────── 글 ───────────────────────────

    /**
     * 글 목록 한 장.
     *
     * @param viewerId 보는 사람. {@code null} 이면 <b>게스트</b>이고 {@code mine} 은 {@code null} 이다
     */
    public PostPageResponse page(Long viewerId, String board, String cursor, Integer limit) {
        String filter = normalizeBoardFilter(board);
        int size = clamp(limit);

        // 한 줄 더 읽어 hasMore 를 정한다. 별도 count 쿼리는 다음 장을 여는 사이에 값이
        // 바뀌고, 두 번 읽는 비용이 한 줄 더 읽는 비용보다 크다.
        Limit fetch = Limit.of(size + 1);
        List<Post> rows = CommunityCursor.parse(cursor)
                .map(c -> posts.findPageAfter(filter, c.createdAt(), c.id(), fetch))
                .orElseGet(() -> posts.findPage(filter, fetch));

        boolean hasMore = rows.size() > size;
        if (hasMore) {
            rows = rows.subList(0, size);
        }
        if (rows.isEmpty()) {
            return new PostPageResponse(List.of(), null, false);
        }

        List<Long> ids = rows.stream().map(Post::getId).toList();
        Map<Long, ReactionSummaryResponse> reactionsById = summarize(ids, viewerId);
        Map<Long, Integer> commentCounts = countComments(ids);

        List<PostResponse> items = new ArrayList<>(rows.size());
        for (Post p : rows) {
            items.add(PostResponse.of(p,
                    commentCounts.getOrDefault(p.getId(), 0),
                    reactionsById.getOrDefault(p.getId(), emptySummary(viewerId))));
        }

        Post last = rows.get(rows.size() - 1);
        String next = hasMore ? CommunityCursor.of(last.getCreatedAt(), last.getId()) : null;
        return new PostPageResponse(items, next, hasMore);
    }

    /** 글 상세. 없으면 404 다. */
    public PostResponse detail(Long viewerId, long postId) {
        Post post = posts.findDetail(postId).orElseThrow(CommunityService::notFound);
        return PostResponse.of(post,
                countComments(List.of(postId)).getOrDefault(postId, 0),
                summarizeOne(postId, viewerId));
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
                .build());
        return PostResponse.of(saved, 0, emptySummary(me.getId()));
    }

    // ─────────────────────────── 댓글 ───────────────────────────

    public CommentPageResponse comments(long postId, String cursor, Integer limit) {
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

        Comment last = rows.get(rows.size() - 1);
        return new CommentPageResponse(
                rows.stream().map(CommentResponse::of).toList(),
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

    // ─────────────────────────── 반응 ───────────────────────────

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
    private static String displayNameOf(User user) {
        if (user.getNickname() != null && !user.getNickname().isBlank()) {
            return user.getNickname();
        }
        return blankToNull(user.getName());
    }
}
