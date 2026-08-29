// src/main/java/com/heattrip/heat_trip_backend/feedback/controller/FeedbackController.java
package com.heattrip.heat_trip_backend.feedback.controller;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.feedback.dto.FeedbackRequest;
import com.heattrip.heat_trip_backend.feedback.service.FeedbackService;
import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController // JSON 반환 컨트롤러
@RequiredArgsConstructor // 생성자 주입
@RequestMapping // 공용 prefix가 필요하면 value="/api" 등으로 지정
public class FeedbackController {

    private final FeedbackService feedbackService;

    /**
     * 피드백 등록.
     *
     * <p>인증이 <b>필수</b>다. 주석에는 오래도록 "Authorization 헤더는 선택(로그인/비로그인 모두 수집)"
     * 이라고 적혀 있었지만, {@code /feedback} 은 {@code SecurityConfig.publicMatchers} 에 없어
     * #23 이후 비인증 요청은 이 메서드에 닿지 않는다. 주석이 코드보다 오래된 상태였다. (이슈 #5)
     *
     * <p>content 만 필수, 나머지는 선택.
     */
    @PostMapping("/feedback")
    public ResponseEntity<Void> create(
            @CurrentUser User me,
            @RequestBody FeedbackRequest req
    ) {
        if (req.getContent() == null || req.getContent().trim().isEmpty()) {
            // content 없으면 400
            return ResponseEntity.badRequest().build();
        }
        feedbackService.create(me, req);
        return ResponseEntity.ok().build();
    }
}
