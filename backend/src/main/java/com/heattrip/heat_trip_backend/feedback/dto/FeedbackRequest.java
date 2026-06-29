// src/main/java/com/heattrip/heat_trip_backend/feedback/dto/FeedbackRequest.java
package com.heattrip.heat_trip_backend.feedback.dto;

import lombok.*;

/** 클라이언트가 보내는 피드백 요청 바디 */
@Getter @Setter
@NoArgsConstructor @AllArgsConstructor
@Builder
public class FeedbackRequest {
    private String content;     // 필수
    private String category;    // 선택(예: 버그/제안/기타)
    private String appVersion;  // 선택
    private String deviceInfo;  // 선택
}
