// src/main/java/com/heattrip/heat_trip_backend/feedback/controller/FeedbackController.java
package com.heattrip.heat_trip_backend.feedback.controller;

import com.heattrip.heat_trip_backend.feedback.dto.FeedbackRequest;
import com.heattrip.heat_trip_backend.feedback.service.FeedbackService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController // JSON 반환 컨트롤러
@RequiredArgsConstructor // 생성자 주입
@RequestMapping // 공용 prefix가 필요하면 value="/api" 등으로 지정
public class FeedbackController {

    private final FeedbackService feedbackService;

    /**
     * 피드백 등록
     * - Authorization 헤더는 '선택' (로그인/비로그인 모두 수집 가능)
     * - content만 필수, 나머지는 선택
     */
    @PostMapping("/feedback")
    public ResponseEntity<Void> create(
            @RequestHeader(value = "Authorization", required = false) String authHeader,
            @RequestBody FeedbackRequest req
    ) {
        if (req.getContent() == null || req.getContent().trim().isEmpty()) {
            // content 없으면 400
            return ResponseEntity.badRequest().build();
        }
        feedbackService.create(authHeader, req);
        return ResponseEntity.ok().build();
    }
}
