package com.heattrip.heat_trip_backend.community.controller;

import com.heattrip.heat_trip_backend.OAuth.principal.AuthenticatedUser;
import com.heattrip.heat_trip_backend.community.dto.CommentPageResponse;
import com.heattrip.heat_trip_backend.community.dto.CommentRequest;
import com.heattrip.heat_trip_backend.community.dto.CommentResponse;
import com.heattrip.heat_trip_backend.community.dto.PostPageResponse;
import com.heattrip.heat_trip_backend.community.dto.PostRequest;
import com.heattrip.heat_trip_backend.community.dto.PostResponse;
import com.heattrip.heat_trip_backend.community.dto.ReactionSummaryResponse;
import com.heattrip.heat_trip_backend.community.service.CommunityService;
import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.entity.User;

import jakarta.validation.Valid;

import org.springframework.http.HttpStatus;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * 커뮤니티 HTTP 표면 — 이슈 #170.
 *
 * <h2>인증이 두 갈래다</h2>
 * <p><b>쓰기 넷</b>은 {@code @CurrentUser User me} 하나로 받는다. 주입 실패는 전부 본문 없는
 * 401 이고 그 판정은 {@code CurrentUserArgumentResolver} 한 곳뿐이다(#5).
 *
 * <p><b>읽기 셋</b>은 <b>인증이 선택</b>이라 {@code @CurrentUser} 를 <b>쓸 수 없다</b> — 그것은
 * 실패를 401 로 만드는 것이 설계라 게스트를 못 받는다. 대신 {@link #viewerId()} 가 필터가 채운
 * {@code SecurityContext} 에서 직접 읽는다.
 *
 * <p>새 애노테이션도 새 리졸버도 만들지 않았다(ADR-0016 결정 3). {@code @CurrentUser} 는
 * 스스로 <b>"{@code required=false} 같은 것을 두면 '인증이 선택인 엔드포인트' 라는 개념이
 * 되살아난다"</b> 고 적어 뒀고, 새 애노테이션은 springdoc 무시 등록을 함께 해야 하는데
 * 빠뜨리면 생성 계약이 조용히 오염된다.
 *
 * <p>이 클래스는 {@code Authorization} 헤더를 <b>다시 읽지 않는다</b> —
 * {@code AuthSubjectContractSpecTest} 가 소스 스캔으로 막는 자리다.
 *
 * <h2>{@code ResponseEntity<?>} 를 쓰지 않는다</h2>
 * <p>DTO 를 그대로 반환하고 상태 코드는 {@code @ResponseStatus} 로 붙인다. {@code ResponseEntity<?>}
 * 는 springdoc 이 응답 스키마를 못 읽어 <b>생성 계약이 비어 버린다.</b> {@code walk}·{@code dog}
 * 이 그 모양이다.
 *
 * <h2>오류 봉투를 여기서 만들지 않는다</h2>
 * <p>검증 실패는 {@code IllegalArgumentException}, 없는 글은
 * {@code ResponseStatusException(NOT_FOUND)}. 봉투는 {@code GlobalExceptionHandler} 하나가
 * 만든다(#10 이 봉투를 하나로 합쳤다).
 */
@RestController
@RequestMapping("/api/community")
public class CommunityController {

    private final CommunityService community;

    public CommunityController(CommunityService community) {
        this.community = community;
    }

    // ─────────────────────────── 읽기 (인증 선택) ───────────────────────────

    @GetMapping("/posts")
    public PostPageResponse feed(@RequestParam(required = false) String board,
                                 @RequestParam(required = false) String cursor,
                                 @RequestParam(required = false) Integer limit) {
        return community.page(viewerId(), board, cursor, limit);
    }

    @GetMapping("/posts/{postId}")
    public PostResponse detail(@PathVariable long postId) {
        return community.detail(viewerId(), postId);
    }

    @GetMapping("/posts/{postId}/comments")
    public CommentPageResponse comments(@PathVariable long postId,
                                        @RequestParam(required = false) String cursor,
                                        @RequestParam(required = false) Integer limit) {
        return community.comments(postId, cursor, limit);
    }

    // ─────────────────────────── 쓰기 (인증 필수) ───────────────────────────

    @PostMapping("/posts")
    @ResponseStatus(HttpStatus.CREATED)
    public PostResponse create(@CurrentUser User me, @Valid @RequestBody PostRequest request) {
        return community.create(me, request);
    }

    @PostMapping("/posts/{postId}/comments")
    @ResponseStatus(HttpStatus.CREATED)
    public CommentResponse addComment(@CurrentUser User me,
                                      @PathVariable long postId,
                                      @Valid @RequestBody CommentRequest request) {
        return community.addComment(me, postId, request);
    }

    /**
     * 내 글을 지운다 — 이슈 #211.
     *
     * <p><b>댓글과 반응이 함께 사라진다</b>(FK CASCADE). 남의 글이면 404 가 아니라
     * <b>403</b> 이다 — 글은 누구나 읽을 수 있어서 존재가 이미 공개다. 이유는 서비스 javadoc.
     */
    @DeleteMapping("/posts/{postId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deletePost(@CurrentUser User me, @PathVariable long postId) {
        community.deletePost(me, postId);
    }

    /** 내 댓글을 지운다. 글 주인이라도 남의 댓글은 못 지운다 — 관리는 #166 이 갖는다. */
    @DeleteMapping("/posts/{postId}/comments/{commentId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteComment(@CurrentUser User me,
                              @PathVariable long postId,
                              @PathVariable long commentId) {
        community.deleteComment(me, postId, commentId);
    }

    /** 멱등이다 — 이미 눌러 뒀어도 200 이고 집계가 늘지 않는다. */
    @PostMapping("/posts/{postId}/reactions/{type}")
    public ReactionSummaryResponse addReaction(@CurrentUser User me,
                                               @PathVariable long postId,
                                               @PathVariable String type) {
        return community.addReaction(me, postId, type);
    }

    /** 멱등이다 — 안 눌렀던 것을 취소해도 200 이다. */
    @DeleteMapping("/posts/{postId}/reactions/{type}")
    public ReactionSummaryResponse removeReaction(@CurrentUser User me,
                                                  @PathVariable long postId,
                                                  @PathVariable String type) {
        return community.removeReaction(me, postId, type);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 보는 사람의 id. <b>토큰이 없거나 깨졌으면 {@code null}</b> 이고 그것이 게스트다.
     *
     * <p>{@code JWTAuthenticationFilter} 는 permitAll 경로에도 전부 걸리고, 토큰이 유효할 때만
     * principal 을 {@link AuthenticatedUser} 로 채운다. 아니면 {@code SecurityContext} 를
     * 비운 채 통과시킨다 — 여기가 그 두 상태를 가르는 유일한 자리다.
     *
     * <p><b>만료 토큰도 게스트로 떨어진다.</b> 필터가 깨진 토큰을 조용히 무시하므로 401 이
     * 아니라 200 + {@code mine: null} 이 나가고, 앱은 401 에서만 토큰을 갱신한다. 창은
     * "앱을 켠 뒤 커뮤니티 읽기만 만지는 한 세션" 이다 — 다시 켜면 {@code GET /auth/me} 가
     * 반드시 401 을 준다(ADR-0016 결정 3의 결과 절).
     *
     * <p>DB 를 읽지 않는다. 필요한 것이 id 뿐이라 사용자 행을 올릴 이유가 없다 —
     * {@code AuthenticatedUser} javadoc 이 같은 이유로 그 타입을 DB 와 떼어 놨다.
     */
    private static Long viewerId() {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication == null
                || !(authentication.getPrincipal() instanceof AuthenticatedUser principal)) {
            return null;
        }
        return principal.id();
    }
}
