package com.heattrip.heat_trip_backend.social.controller;

import java.util.List;
import java.util.Map;

import org.springframework.http.HttpStatus;
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

    /** POST /api/social/cards — 현재 사용자로 카드 공유. */
    @PostMapping("/cards")
    public ResponseEntity<?> shareCard(@RequestBody ShareCardRequest req, @CurrentUser User user) {
        try {
            EmotionCard saved = socialService.share(
                    user.getId(),
                    req.getHandle(),
                    req.getMoodKey(),
                    req.getBody(),
                    req.getPlaceName(),
                    req.getPlaceId()
            );
            CardDto dto = socialService.toDto(saved, user.getId());
            return ResponseEntity.ok(dto);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to share card"));
        }
    }

    /** GET /api/social/cards?limit=50 — 최신순 피드. */
    @GetMapping("/cards")
    public ResponseEntity<?> feed(@RequestParam(value = "limit", defaultValue = "50") Integer limit,
                                  @CurrentUser User user) {
        try {
            List<CardDto> feed = socialService.feed(user.getId(), limit);
            return ResponseEntity.ok(feed);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to load feed"));
        }
    }

    /** POST /api/social/cards/{id}/reactions — 리액션 토글. */
    @PostMapping("/cards/{id}/reactions")
    public ResponseEntity<?> toggleReaction(@PathVariable("id") Long cardId,
                                            @RequestBody ReactionRequest req,
                                            @CurrentUser User user) {
        try {
            Map<String, Object> result = socialService.toggleReaction(cardId, user.getId(), req.getType());
            return ResponseEntity.ok(result);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to toggle reaction"));
        }
    }

    /** POST /api/social/cards/{id}/comments — 현재 사용자로 댓글 작성. */
    @PostMapping("/cards/{id}/comments")
    public ResponseEntity<?> addComment(@PathVariable("id") Long cardId,
                                        @RequestBody CommentRequest req,
                                        @CurrentUser User user) {
        try {
            CommentDto dto = socialService.addComment(cardId, user.getId(), req.getHandle(), req.getBody());
            return ResponseEntity.ok(dto);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to add comment"));
        }
    }

    /** GET /api/social/cards/{id}/comments — 댓글 목록(오래된 순). */
    @GetMapping("/cards/{id}/comments")
    public ResponseEntity<?> comments(@PathVariable("id") Long cardId,
                                      // 본문에서 쓰지 않지만 선언이 곧 인증 요구다 — 예전 requireUser(request)
                                      // 호출이 하던 역할을 그대로 대신한다.
                                      @CurrentUser User user) {
        try {
            List<CommentDto> comments = socialService.comments(cardId);
            return ResponseEntity.ok(comments);
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to load comments"));
        }
    }
}
