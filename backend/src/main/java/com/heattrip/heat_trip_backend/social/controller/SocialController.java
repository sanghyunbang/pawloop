package com.heattrip.heat_trip_backend.social.controller;

import java.util.List;
import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.social.dto.CardDto;
import com.heattrip.heat_trip_backend.social.dto.CommentDto;
import com.heattrip.heat_trip_backend.social.dto.CommentRequest;
import com.heattrip.heat_trip_backend.social.dto.ReactionRequest;
import com.heattrip.heat_trip_backend.social.dto.ShareCardRequest;
import com.heattrip.heat_trip_backend.social.entity.EmotionCard;
import com.heattrip.heat_trip_backend.social.service.SocialService;
import com.heattrip.heat_trip_backend.user.entity.User;

/**
 * "함께"(together) 소셜 피드 API.
 * SecurityConfig.anyRequest().authenticated() 에 의해 /api/social/** 는 자동으로 인증이 요구된다.
 */
@RestController
@RequestMapping("/api/social")
public class SocialController {

    private final SocialService socialService;

    public SocialController(SocialService socialService) {
        this.socialService = socialService;
    }

    // 예전에는 여기 private User requireUser(HttpServletRequest) 가 있었다. 그 안의
    // ResponseStatusException(401) 은 실제로 401 이 아니라 **500** 으로 나가고 있었다 —
    // GlobalExceptionHandler 의 @ExceptionHandler(Exception.class) 가 DispatcherServlet 안에서
    // 먼저 잡기 때문이다(실측 확인). 인증은 이제 @CurrentUser 가 맡고 실패는 본문 없는 401 이다. (이슈 #5)
    //
    // 다섯 핸들러에 있던 try/catch 두 겹도 사라졌다. 그것들은 오류 본문을
    // {"error": "문자열"} 로 만들었는데, 계약(openapi.yaml 의 Error)은
    // {"error": {"code", "message", "traceId"}} 다 — 같은 앱으로 서로 다른 두 형태가
    // 나가고 있었고, 어느 쪽도 계약이 아니었다. 이제 예외는 그대로 올라가
    // GlobalExceptionHandler 한 곳이 계약 형태로 바꾼다. (이슈 #10)
    //
    // catch (Exception e) 를 지운 것도 의도다. 그 블록은 예상하지 못한 예외를 200 대신
    // 200 짜리 오류 문자열로 바꿔 삼키면서 **스택트레이스를 로그에도 남기지 않았다** —
    // 원인을 찾을 수단이 없었다. 지금은 catch-all 이 상관관계 ID 를 응답에 주고
    // 스택트레이스를 서버 로그에 남긴다.

    /** POST /api/social/cards — 현재 사용자로 카드 공유. */
    @PostMapping("/cards")
    public ResponseEntity<CardDto> shareCard(@RequestBody ShareCardRequest req, @CurrentUser User user) {
        EmotionCard saved = socialService.share(
                user.getId(),
                req.getHandle(),
                req.getMoodKey(),
                req.getBody(),
                req.getPlaceName(),
                req.getPlaceId()
        );
        return ResponseEntity.ok(socialService.toDto(saved, user.getId()));
    }

    /** GET /api/social/cards?limit=50 — 최신순 피드. */
    @GetMapping("/cards")
    public ResponseEntity<List<CardDto>> feed(@RequestParam(value = "limit", defaultValue = "50") Integer limit,
                                              @CurrentUser User user) {
        return ResponseEntity.ok(socialService.feed(user.getId(), limit));
    }

    /** POST /api/social/cards/{id}/reactions — 리액션 토글. */
    @PostMapping("/cards/{id}/reactions")
    public ResponseEntity<Map<String, Object>> toggleReaction(@PathVariable("id") Long cardId,
                                                              @RequestBody ReactionRequest req,
                                                              @CurrentUser User user) {
        return ResponseEntity.ok(socialService.toggleReaction(cardId, user.getId(), req.getType()));
    }

    /** POST /api/social/cards/{id}/comments — 현재 사용자로 댓글 작성. */
    @PostMapping("/cards/{id}/comments")
    public ResponseEntity<CommentDto> addComment(@PathVariable("id") Long cardId,
                                                 @RequestBody CommentRequest req,
                                                 @CurrentUser User user) {
        return ResponseEntity.ok(
                socialService.addComment(cardId, user.getId(), req.getHandle(), req.getBody()));
    }

    /** GET /api/social/cards/{id}/comments — 댓글 목록(오래된 순). */
    @GetMapping("/cards/{id}/comments")
    public ResponseEntity<List<CommentDto>> comments(@PathVariable("id") Long cardId,
                                                     // 본문에서 쓰지 않지만 선언이 곧 인증 요구다 —
                                                     // 예전 requireUser(request) 가 하던 역할이다.
                                                     @CurrentUser User user) {
        return ResponseEntity.ok(socialService.comments(cardId));
    }
}
