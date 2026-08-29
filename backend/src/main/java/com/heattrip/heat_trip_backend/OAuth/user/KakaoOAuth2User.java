package com.heattrip.heat_trip_backend.OAuth.user;

import java.util.Map;

// 구조는 GoogleOAuth2User와 유사합니다.
// KakaoOAuth2User는 OAuth2UserInfo라는 공통 인터페이스를 구현합니다.

/**
 * 카카오 {@code /v2/user/me} 응답을 감싼다.
 *
 * <p>응답 모양은 <b>동의 항목 설정에 따라 달라진다.</b> 콘솔 현황(2026-08):
 * {@code profile_nickname} 필수 동의 · {@code account_email} 선택 동의 · {@code profile_image} 사용 안 함.
 * 즉 {@code kakao_account.email} 은 사용자가 거부하면 키 자체가 없고,
 * {@code kakao_account.profile} 도 통째로 없을 수 있다.
 * 그래서 모든 접근이 <b>키가 없어도, 타입이 달라도</b> null 로 끝나야 한다. (이슈 #7)
 */
public class KakaoOAuth2User implements OAuth2UserInfo {

    private final Map<String, Object> attributes;

    public KakaoOAuth2User(Map<String, Object> attributes) {
        this.attributes = (attributes != null) ? attributes : Map.of();
    }

    @Override
    public String getProvider() {
        return "kakao";
    }

    // 사용자의 고유 ID (카카오는 "id" 필드 사용)
    @Override
    public String getProviderId() {
        // Kakao의 "id" 값은 Long 타입으로 전달되므로,
        // 자바에서 직접 (String) 형변환을 하면 ClassCastException이 발생할 수 있음.
        // 따라서 안전하게 문자열로 바꾸기 위해 String.valueOf(...) 사용.
        // (참고: Google의 "sub" 값은 원래 String 타입이므로 (String) 형변환만 해도 됨)
        //
        // 다만 id 가 없을 때 String.valueOf(null) 은 문자열 "null" 을 만든다.
        // 그 값이 social_id 로 저장되면 서로 다른 사용자가 한 행을 공유하게 된다. 반드시 null 로 돌려준다.
        Object id = attributes.get("id");
        return (id != null) ? String.valueOf(id) : null;
    }

    // 사용자의 이메일 주소
    @Override
    public String getEmail() {
        // kakao_account -> email (중첩된 JSON 구조). 선택 동의라 키가 없을 수 있다.
        return asString(nested("kakao_account").get("email"));
    }

    // 사용자의 이름 (카카오는 nickname)
    @Override
    public String getName() {
        // kakao_account -> profile -> nickname
        return asString(nestedIn(nested("kakao_account"), "profile").get("nickname"));
    }

    @Override
    public String getImageUrl() {
        // profile_image 는 콘솔에서 '사용 안 함' 이라 보통 키가 없다. 켜지면 값이 들어온다.
        Map<String, Object> profile = nestedIn(nested("kakao_account"), "profile");
        String thumbnail = asString(profile.get("profile_image_url"));
        return (thumbnail != null) ? thumbnail : asString(profile.get("thumbnail_image_url"));
    }

    // 필요시 전체 사용자 정보(JSON)을 반환할 수 있도록 추가
    public Map<String, Object> getAttributes() {
        return attributes;
    }

    /** 최상위에서 중첩 맵을 꺼낸다. 없거나 맵이 아니면 빈 맵. */
    private Map<String, Object> nested(String key) {
        return nestedIn(attributes, key);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> nestedIn(Map<String, Object> source, String key) {
        Object value = source.get(key);
        return (value instanceof Map) ? (Map<String, Object>) value : Map.of();
    }

    /** 문자열이 아니면(공급자 스키마가 바뀌면) 캐스팅으로 죽지 말고 null 로 본다. */
    private static String asString(Object value) {
        return (value instanceof String s) ? s : null;
    }
}
