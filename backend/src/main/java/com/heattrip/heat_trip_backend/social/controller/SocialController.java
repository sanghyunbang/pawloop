package com.heattrip.heat_trip_backend.social.controller;

import java.util.List;
import java.util.Map;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.social.dto.CardDto;
import com.heattrip.heat_trip_backend.social.dto.CommentDto;
import com.heattrip.heat_trip_backend.social.dto.CommentRequest;
import com.heattrip.heat_trip_backend.social.dto.ReactionRequest;
import com.heattrip.heat_trip_backend.social.dto.ShareCardRequest;
import com.heattrip.heat_trip_backend.social.entity.EmotionCard;
import com.heattrip.heat_trip_backend.social.service.SocialService;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.service.UserService;

import jakarta.servlet.http.HttpServletRequest;

/**
 * "함께"(together) 소셜 피드 API.
 * SecurityConfig.anyRequest().authenticated() 에 의해 /api/social/** 는 자동으로 인증이 요구된다.
 */
@RestController
@RequestMapping("/api/social")
public class SocialController {

    private final SocialService socialService;
    private final JWTProvider jwtProvider;
    private final UserService userService;

    public SocialController(SocialService socialService,
                            JWTProvider jwtProvider,
                            UserService userService) {
        this.socialService = socialService;
        this.jwtProvider = jwtProvider;
        this.userService = userService;
    }

    /** JWT에서 현재 사용자 추출(JourneyController_v2 와 동일 패턴). 없으면 401. */
    private User requireUser(HttpServletRequest request) {
        String authHeader = request.getHeader("Authorization");
        if (authHeader == null || !authHeader.startsWith("Bearer "))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthorized");

        String token = authHeader.substring(7);
        if (!jwtProvider.validateToken(token))
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthorized");

        String email = jwtProvider.getUserIdFromToken(token); // 토큰 subject = email
        User user = userService.findByEmail(email);
        if (user == null)
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Unauthorized");

        return user;
    }

    /** POST /api/social/cards — 현재 사용자로 카드 공유. */
    @PostMapping("/cards")
    public ResponseEntity<?> shareCard(@RequestBody ShareCardRequest req, HttpServletRequest request) {
        User user = requireUser(request);
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
                                  HttpServletRequest request) {
        User user = requireUser(request);
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
                                            HttpServletRequest request) {
        User user = requireUser(request);
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
                                        HttpServletRequest request) {
        User user = requireUser(request);
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
                                      HttpServletRequest request) {
        requireUser(request);
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
