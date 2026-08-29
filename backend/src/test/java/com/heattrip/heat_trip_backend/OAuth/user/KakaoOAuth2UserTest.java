package com.heattrip.heat_trip_backend.OAuth.user;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;

/**
 * 카카오 응답의 <b>변형</b>을 견디는지 본다 — 이슈 #7 · 정책 #21("외부 응답의 변형").
 *
 * <p>카카오 콘솔(2026-08): {@code profile_nickname} 필수 동의 · {@code account_email} 선택 동의 ·
 * {@code profile_image} 사용 안 함. 즉 이메일 키가 아예 없는 응답이 정상 응답이다.
 * 실제 '동의 거부' 상황은 콘솔 상태에 달려 재현할 수 없으므로,
 * {@code getEmail()} 에 들어오는 입력으로서 동등한 "키 없는 맵"으로 대체한다.
 */
class KakaoOAuth2UserTest {

    private static final String SOCIAL_ID = "1234567890";

    @Test
    @DisplayName("provider 는 항상 kakao 이고 id 는 Long 이어도 문자열로 나온다")
    void provider_andProviderId() {
        KakaoOAuth2User user = new KakaoOAuth2User(Map.of("id", 1234567890L));

        assertThat(user.getProvider()).isEqualTo("kakao");
        assertThat(user.getProviderId()).isEqualTo(SOCIAL_ID);
    }

    @Test
    @DisplayName("id 가 없으면 providerId 는 문자열 \"null\" 이 아니라 진짜 null 이다")
    void providerId_isNullNotTheStringNull() {
        // String.valueOf(null) 은 "null" 을 만든다. 그 값이 social_id 로 저장되면
        // id 를 못 받은 사용자들이 한 행을 공유하게 된다.
        assertThat(new KakaoOAuth2User(Map.of()).getProviderId()).isNull();
    }

    @Nested
    @DisplayName("이메일·닉네임이 없는 응답에도 예외 없이 null 을 돌려준다")
    class MissingKeys {

        @Test
        @DisplayName("kakao_account 키 자체가 없는 맵")
        void noKakaoAccount() {
            KakaoOAuth2User user = new KakaoOAuth2User(Map.of("id", SOCIAL_ID));

            assertThatCode(user::getEmail).doesNotThrowAnyException();
            assertThat(user.getEmail()).isNull();
            assertThat(user.getName()).isNull();
            assertThat(user.getImageUrl()).isNull();
        }

        @Test
        @DisplayName("kakao_account 는 있으나 email 키가 없는 맵 — 이메일 동의를 거부한 사용자")
        void kakaoAccountWithoutEmail() {
            Map<String, Object> attributes = Map.of(
                    "id", SOCIAL_ID,
                    "kakao_account", Map.of("profile", Map.of("nickname", "보리아빠")));

            KakaoOAuth2User user = new KakaoOAuth2User(attributes);

            assertThat(user.getEmail()).isNull();
            assertThat(user.getName()).isEqualTo("보리아빠"); // 닉네임은 필수 동의라 온다
        }

        @Test
        @DisplayName("profile 이 없는 맵")
        void kakaoAccountWithoutProfile() {
            Map<String, Object> attributes = Map.of(
                    "id", SOCIAL_ID,
                    "kakao_account", Map.of("email", "bori@example.com"));

            KakaoOAuth2User user = new KakaoOAuth2User(attributes);

            assertThat(user.getName()).isNull();
            assertThat(user.getImageUrl()).isNull();
            assertThat(user.getEmail()).isEqualTo("bori@example.com");
        }

        @Test
        @DisplayName("attributes 가 통째로 null 이어도 죽지 않는다")
        void nullAttributes() {
            KakaoOAuth2User user = new KakaoOAuth2User(null);

            assertThatCode(() -> {
                user.getProviderId();
                user.getEmail();
                user.getName();
                user.getImageUrl();
            }).doesNotThrowAnyException();
        }

        @Test
        @DisplayName("중첩 값의 타입이 예상과 다르면 ClassCastException 대신 null 이다")
        void unexpectedTypes() {
            Map<String, Object> attributes = new HashMap<>();
            attributes.put("id", SOCIAL_ID);
            attributes.put("kakao_account", "문자열이 왔다"); // 공급자 스키마가 바뀐 상황

            KakaoOAuth2User user = new KakaoOAuth2User(attributes);

            assertThat(user.getEmail()).isNull();
            assertThat(user.getName()).isNull();
        }
    }

    @Test
    @DisplayName("profile_image 동의를 켜면 프로필 이미지 URL 이 나온다")
    void imageUrl_whenProfileImageConsented() {
        Map<String, Object> attributes = Map.of(
                "id", SOCIAL_ID,
                "kakao_account", Map.of("profile", Map.of(
                        "nickname", "보리아빠",
                        "profile_image_url", "https://img.kakaocdn.net/bori.jpg")));

        assertThat(new KakaoOAuth2User(attributes).getImageUrl())
                .isEqualTo("https://img.kakaocdn.net/bori.jpg");
    }

    @Test
    @DisplayName("profile_image_url 이 없으면 thumbnail_image_url 로 떨어진다")
    void imageUrl_fallsBackToThumbnail() {
        Map<String, Object> attributes = Map.of(
                "id", SOCIAL_ID,
                "kakao_account", Map.of("profile", Map.of(
                        "thumbnail_image_url", "https://img.kakaocdn.net/thumb.jpg")));

        assertThat(new KakaoOAuth2User(attributes).getImageUrl())
                .isEqualTo("https://img.kakaocdn.net/thumb.jpg");
    }
}
