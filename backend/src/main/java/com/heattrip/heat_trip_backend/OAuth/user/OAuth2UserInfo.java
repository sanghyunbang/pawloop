package com.heattrip.heat_trip_backend.OAuth.user;

/**
 * 공급자별 응답(구글/카카오/네이버)을 하나의 모양으로 맞춰 주는 인터페이스.
 *
 * <p><b>{@code getProvider()} + {@code getProviderId()} 만 항상 값이 있다.</b>
 * 나머지는 전부 null 일 수 있다 — 공급자 동의 항목에 달려 있기 때문이다.
 * 예: 카카오 {@code account_email} 은 선택 동의, {@code profile_image} 는 사용 안 함.
 * 구현체는 키가 없어도 예외를 던지지 말고 null 을 돌려준다. (이슈 #7)
 */
public interface OAuth2UserInfo {
    String getProvider(); // e.g., "google", "kakao", "naver"

    String getProviderId(); // Unique ID for the user in the provider's system

    /** 이메일. 동의하지 않았거나 공급자가 주지 않으면 null. */
    String getEmail();

    /** 표시 이름. 구글은 {@code name}, 카카오는 {@code nickname}. 없으면 null. */
    String getName();

    /**
     * 프로필 이미지 URL. 없으면 null.
     *
     * <p>기본 구현이 null 인 이유: 공급자가 이미지를 아예 내려주지 않는 설정이 흔하다
     * (카카오 콘솔의 {@code profile_image} 는 현재 '사용 안 함').
     * 구현체가 이 메서드를 덮지 않아도 로그인은 정상 동작해야 한다.
     */
    default String getImageUrl() {
        return null;
    }
}
