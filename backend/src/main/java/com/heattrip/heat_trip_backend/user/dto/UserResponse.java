// DTO(UserResponse) 로 필요한 필드만 리턴 → 민감정보 차단, API 스펙 고정, 내부 스키마 변경 영향 최소화, 순환참조/지연로딩 문제 예방.
package com.heattrip.heat_trip_backend.user.dto;

import com.heattrip.heat_trip_backend.user.NeighborhoodCatalog;
import com.heattrip.heat_trip_backend.user.UserTime;
import com.heattrip.heat_trip_backend.user.entity.User;
import lombok.*;

import java.time.Instant;

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
@Builder(toBuilder = true)
public class UserResponse {
    private Long id;
    private String name;
    private String nickname;
    private String gender;     // "FEMALE" / "MALE" / "OTHER"
    private Integer age;
    private String email;      // 소셜 공급자가 이메일을 주지 않으면 null
    private String travelType; // 현재 스키마는 단일 문자열
    private String imageUrl;
    private String provider;   // "local" / "kakao" / "google" / "apple"(#301) — 계약의 User.provider (naver 는 ADR-0010 에서 보류)
    /** 가입 시각. <b>오프셋이 붙는다</b> — 컬럼 값은 UTC 다({@link UserTime}). #248 */
    private Instant createdAt;
    /** 마지막 수정 시각. 같은 규약이다. */
    private Instant updatedAt;

    /**
     * 내가 고른 동네 (#342). 안 골랐으면 {@code null} 이다.
     *
     * <p><b>동 이름은 안 싣는다.</b> 서버가 아는 것은 시군구까지이고(이유는
     * {@code NeighborhoodCatalog}), 앱은 자기가 고른 동 이름을 이미 기기에 들고 있다.
     */
    private Neighborhood neighborhood;

    /** 코드와 이름 셋. 좌표는 없다 — 서버는 그것을 받지도 저장하지도 않는다(#235 A안). */
    @Getter @Setter
    @NoArgsConstructor @AllArgsConstructor
    @Builder
    public static class Neighborhood {
        private String code;      // 행정동 열 자리 — 사용자가 고른 그 값
        private String sido;      // 서울특별시
        private String sigungu;   // 성동구 — 글 카드에 보이는 단위
    }

    /**
     * @param sigungu 그 사용자의 시군구. {@code NeighborhoodCatalog.find} 가 준 값이고,
     *                동네를 안 골랐거나 모르는 코드면 {@code null} 이다.
     *                <b>인자로 받는 이유</b>: 표를 아는 것은 카탈로그 하나뿐이라 DTO 가 그것을
     *                직접 부르면 정적 상태가 생긴다. 부르는 쪽마다 "동네를 실을까" 를
     *                의식적으로 정하게 두는 편이 낫다.
     */
    public static UserResponse from(User u, NeighborhoodCatalog.Sigungu sigungu) {
        return from(u).toBuilder()
                .neighborhood(sigungu == null || u.getNeighborhoodCode() == null
                        ? null
                        : Neighborhood.builder()
                                .code(u.getNeighborhoodCode())
                                .sido(sigungu.sido())
                                .sigungu(sigungu.name())
                                .build())
                .build();
    }

    /** 동네를 안 싣는 응답. 로그인·가입처럼 그 값이 화면에 필요 없는 자리에서 쓴다. */
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
                .createdAt(UserTime.toInstant(u.getCreatedAt()))
                .updatedAt(UserTime.toInstant(u.getUpdatedAt()))
                .build();
    }
}
