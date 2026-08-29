// src/main/java/com/heattrip/heat_trip_backend/feedback/service/FeedbackService.java
package com.heattrip.heat_trip_backend.feedback.service;

import com.heattrip.heat_trip_backend.feedback.dto.FeedbackRequest;
import com.heattrip.heat_trip_backend.feedback.entity.Feedback;
import com.heattrip.heat_trip_backend.feedback.repository.FeedbackRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/** 비즈니스 로직 계층 */
@Service // 서비스 빈 등록(컴포넌트 스캔 대상)
@RequiredArgsConstructor // final 필드 생성자 자동 주입
public class FeedbackService {

    private final FeedbackRepository feedbackRepository;

    /**
     * 피드백 저장.
     *
     * <p>예전에는 여기서 Authorization 헤더를 직접 파싱하고 "토큰이 없거나 유효하지 않으면 익명"이라는
     * 분기를 뒀다. <b>그 분기는 도달 불가능했고 주석도 사실이 아니었다.</b> (이슈 #5)
     * <ul>
     *   <li>{@code /feedback} 은 {@code SecurityConfig.publicMatchers} 에 없어
     *       {@code anyRequest().authenticated()} 로 떨어진다 — #23 이후 비인증 요청은
     *       컨트롤러에 닿지도 못한다.</li>
     *   <li>{@code UserService.findByEmail} 은 못 찾으면 null 이 아니라 예외를 던졌으므로
     *       "없으면 null" 이라는 주석도 거짓이었다.</li>
     * </ul>
     * 즉 인가 계층과 서비스 계층이 서로 다른 정책을 말하고 있었다. 인가 계층이 정본이다.
     * 익명 피드백을 살리려면 {@code publicMatchers} 에 {@code /feedback} 을 넣는 <b>제품 결정</b>이 먼저다.
     */
    @Transactional
    public void create(User user, FeedbackRequest req) {
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
