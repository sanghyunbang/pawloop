// DTO(UserResponse) 로 필요한 필드만 리턴 → 민감정보 차단, API 스펙 고정, 내부 스키마 변경 영향 최소화, 순환참조/지연로딩 문제 예방.
package com.heattrip.heat_trip_backend.user.dto;

import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.*;

import java.time.LocalDateTime;

@Getter @Setter
@NoArgsConstructor @AllArgsConstructor
@Builder
public class UserResponse {
    private Long id;
    private String name;
    private String nickname;
    private String gender;     // "FEMALE" / "MALE" / "OTHER"
    private Integer age;
    private String email;
    private String travelType; // 현재 스키마는 단일 문자열
    private String imageUrl;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public static UserResponse from(User u) {
        return UserResponse.builder()
                .id(u.getId())
                .name(u.getName())
                .nickname(u.getNickname())
                .gender(u.getGender() != null ? u.getGender().name() : "OTHER")
                .age(u.getAge())
                .email(u.getEmail())
                .travelType(u.getTravelType())
                .imageUrl(u.getImageUrl())
                .createdAt(u.getCreatedAt())
                .updatedAt(u.getUpdatedAt())
                .build();
    }
}
