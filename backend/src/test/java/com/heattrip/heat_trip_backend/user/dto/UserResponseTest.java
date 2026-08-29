package com.heattrip.heat_trip_backend.user.dto;

import com.heattrip.heat_trip_backend.user.entity.User;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * {@code GET /auth/me} 응답이 계약(docs/04-api/openapi.yaml 의 {@code User})과 같은 모양인지 본다.
 * 이슈 #7 · 정책 #21("계약과의 정합").
 */
class UserResponseTest {

    @Test
    @DisplayName("provider 를 그대로 담는다 — 계약의 User.provider")
    void from_mapsProvider() {
        User kakaoUser = User.builder()
                .id(1L).provider("kakao").socialId("1234567890").nickname("보리아빠")
                .build();

        assertThat(UserResponse.from(kakaoUser).getProvider()).isEqualTo("kakao");
    }

    @Test
    @DisplayName("이메일 가입자는 provider 가 local 이다")
    void from_mapsLocalProvider() {
        User localUser = User.builder()
                .id(2L).provider(User.PROVIDER_LOCAL).email("bori@example.com").nickname("보리아빠")
                .build();

        assertThat(UserResponse.from(localUser).getProvider()).isEqualTo("local");
    }

    @Test
    @DisplayName("email 이 null 이어도 NPE 없이 매핑된다 — 이메일 동의를 거부한 카카오 계정")
    void from_doesNotThrowWhenEmailIsNull() {
        User noEmail = User.builder()
                .id(3L).provider("kakao").socialId("1234567890").email(null).nickname("보리아빠")
                .build();

        assertThatCode(() -> UserResponse.from(noEmail)).doesNotThrowAnyException();

        UserResponse response = UserResponse.from(noEmail);
        assertThat(response.getEmail()).isNull();
        assertThat(response.getId()).isEqualTo(3L);   // 계약상 required 인 유일한 필드
        assertThat(response.getNickname()).isEqualTo("보리아빠");
        assertThat(response.getGender()).isEqualTo("OTHER"); // gender 가 null 이면 OTHER 로 떨어진다
    }

    @Test
    @DisplayName("provider 가 아직 백필되지 않은 옛 행은 provider 가 null 이다 — 계약이 null 을 허용한다")
    void from_allowsNullProvider() {
        User legacy = User.builder().id(4L).nickname("보리아빠").build();

        assertThat(UserResponse.from(legacy).getProvider()).isNull();
    }

    @Test
    @DisplayName("isNew 는 이 응답에 없다 — 계약상 AuthTokens 의 1회성 속성이다(#23)")
    void from_hasNoIsNewField() {
        // /auth/me 는 언제든 다시 호출되는 조회다. "이번에 새로 가입했는가"라는 질문이 성립하지 않는다.
        // 계약도 User 가 아니라 AuthTokens 에 isNew 를 둔다 — AuthContractSpecTest 가 그걸 지킨다.
        assertThat(Arrays.stream(UserResponse.class.getDeclaredFields()).map(f -> f.getName()))
                .doesNotContain("isNew");
    }
}
