// src/main/java/com/heattrip/heat_trip_backend/feedback/service/FeedbackService.java
package com.heattrip.heat_trip_backend.feedback.service;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.feedback.dto.FeedbackRequest;
import com.heattrip.heat_trip_backend.feedback.entity.Feedback;
import com.heattrip.heat_trip_backend.feedback.repository.FeedbackRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.service.UserService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 비즈니스 로직 계층 */
@Service // 서비스 빈 등록(컴포넌트 스캔 대상)
@RequiredArgsConstructor // final 필드 생성자 자동 주입
public class FeedbackService {

    private final FeedbackRepository feedbackRepository;
    private final JWTProvider jwtProvider; // 토큰 파싱/검증
    private final UserService userService; // 토큰의 subject(email)로 사용자 로드

    /** 피드백 저장 */
    @Transactional
    public void create(String authHeader, FeedbackRequest req) {
        // 로그인 사용자 연동(토큰 없거나 유효하지 않으면 익명 처리)
        User user = null;
        if (authHeader != null && authHeader.startsWith("Bearer ")) {
            String token = authHeader.substring(7);
            if (jwtProvider.validateToken(token)) {
                String email = jwtProvider.getUserIdFromToken(token); // subject에 email 저장
                user = userService.findByEmail(email); // 없으면 null
            }
        }

        Feedback feedback = Feedback.builder()
                .user(user)
                .content(req.getContent())
                .category(req.getCategory())
                .appVersion(req.getAppVersion())
                .deviceInfo(req.getDeviceInfo())
                .build();

        feedbackRepository.save(feedback);

        // (선택) 운영 알림: 이메일/Slack 등 연결하고 싶으면 여기서 트리거
        // notifyAdmin(feedback);
    }
}
