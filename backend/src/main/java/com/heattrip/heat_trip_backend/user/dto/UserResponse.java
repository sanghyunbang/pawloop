// DTO(UserResponse) 로 필요한 필드만 리턴 → 민감정보 차단, API 스펙 고정, 내부 스키마 변경 영향 최소화, 순환참조/지연로딩 문제 예방.
package com.heattrip.heat_trip_backend.user.dto;

import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.*;

import java.time.LocalDateTime;

/**
 * {@code GET /auth/me} 응답. 계약(docs/04-api/openapi.yaml)의 {@code User} 스키마에 대응한다.
 *
 * <p><b>{@code isNew} 는 여기에 없다.</b> 계약상 {@code isNew} 는 로그인 응답
 * ({@code AuthTokens})의 1회성 이벤트 속성이지 사용자 프로필의 영속 속성이 아니다(#23).
 * {@code /auth/me} 는 언제든 다시 호출되는 조회라서 "새로 가입했는가"라는 질문 자체가 성립하지 않는다.
 * 신규 가입 여부는 {@code CustomOAuth2User.isNew()} 로 로그인 응답까지만 전달된다. (이슈 #7)
 */
@Getter @Setter
@NoArgsConstructor @AllArgsConstructor
@Builder
public class UserResponse {
    private Long id;
    private String name;
    private String nickname;
    private String gender;     // "FEMALE" / "MALE" / "OTHER"
    private Integer age;
    private String email;      // 소셜 공급자가 이메일을 주지 않으면 null
    private String travelType; // 현재 스키마는 단일 문자열
    private String imageUrl;
    private String provider;   // "local" / "kakao" / "google" — 계약의 User.provider (naver 는 ADR-0010 에서 보류)
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
                .provider(u.getProvider())
                .createdAt(u.getCreatedAt())
                .updatedAt(u.getUpdatedAt())
                .build();
    }
}
