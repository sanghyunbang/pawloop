package com.heattrip.heat_trip_backend.chatweb;

import static org.assertj.core.api.Assertions.assertThat;

import com.heattrip.heat_trip_backend.group.service.FamilyGroupService;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

/**
 * 만 14세 게이트가 쓰는 문자열이 가족 도메인의 것과 같은가 — 이슈 #82 완료 조건 5.
 *
 * <h2>왜 이 테스트가 필요한가</h2>
 * <p>{@code chatweb} 의 {@code allowedDependencies} 는 {@code chat} 과 {@code user} 뿐이라
 * {@code group.FamilyGroupService.ORIGIN_KIND} 를 <b>못 본다.</b> 그래서 그 문자열을
 * {@link MinorRoomPolicy} 에 한 번 더 적었고, 그 순간 <b>두 벌이 됐다.</b>
 *
 * <p>테스트는 모듈 경계 밖이라 둘 다 볼 수 있다. 한쪽만 바뀌면 여기가 빨간불이다.
 *
 * <p>이런 종류의 실패는 조용하다 — 문자열이 갈리면 예외도 로그도 없고, <b>만 14세 미만이
 * 가족 방에도 못 들어가게</b> 된다. 그게 사고로 보이지 않는 것이 문제다.
 */
class MinorRoomPolicyTest {

    @Test
    @DisplayName("가족 방을 가리키는 문자열이 group 의 것과 같다")
    void theFamilyOriginKindMatchesTheOwningDomain() {
        assertThat(MinorRoomPolicy.FAMILY_ORIGIN_KIND)
                .as("""
                        갈리면 만 14세 미만이 가족 방에도 못 들어간다. 예외도 로그도 없이
                        그냥 403 이라 사고로 보이지 않는다.
                        """)
                .isEqualTo(FamilyGroupService.ORIGIN_KIND);
    }

    @Test
    @DisplayName("만 14세 미만은 가족 방만 허용된다")
    void aMinorIsLimitedToFamilyRooms() {
        assertThat(MinorRoomPolicy.allowedOriginKindsFor(userAged(User.AgeGroup.UNDER14)))
                .containsExactly(FamilyGroupService.ORIGIN_KIND);
    }

    @Test
    @DisplayName("만 14세 이상은 제한이 없다 — null 이 그 뜻이다")
    void anAdultHasNoRestriction() {
        assertThat(MinorRoomPolicy.allowedOriginKindsFor(userAged(User.AgeGroup.OVER14)))
                .as("빈 집합이 아니라 null 이다. 빈 집합이면 어떤 방에도 못 들어간다")
                .isNull();
    }

    @Test
    @DisplayName("나이대를 모르는 계정은 막지 않는다 — 판단이지 누락이 아니다")
    void anUnknownAgeGroupIsNotTreatedAsAMinor() {
        assertThat(MinorRoomPolicy.allowedOriginKindsFor(userAged(null)))
                .as("""
                        age_group 은 DEFAULT NULL 이고 소셜 로그인으로 들어온 예전 계정들이
                        비어 있다. 여기서 null 을 미성년으로 다루면 그 계정들이 오늘부터
                        방에 못 들어간다 — 아무 예고 없이 기능이 사라지는 쪽이 더 나쁘다.
                        """)
                .isNull();
    }

    private static User userAged(User.AgeGroup ageGroup) {
        return User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("policy@example.com")
                .name("아무개")
                .ageGroup(ageGroup)
                .build();
    }
}
