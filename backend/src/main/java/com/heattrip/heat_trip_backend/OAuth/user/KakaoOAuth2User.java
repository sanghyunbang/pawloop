package com.heattrip.heat_trip_backend.OAuth.user;

import java.util.Map;

// 구조는 GoogleOAuth2User와 유사합니다.
// KakaoOAuth2User는 OAuth2UserInfo라는 공통 인터페이스를 구현합니다.

public class KakaoOAuth2User implements OAuth2UserInfo {
    
    private final Map<String, Object> attributes;

    public KakaoOAuth2User(Map<String, Object> attributes) {
        this.attributes = attributes;
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
        return String.valueOf(attributes.get("id")); 
    }

    // 사용자의 이메일 주소
    @Override
    public String getEmail() {
        // kakao_account -> email(중첩된 JSON 구조)
        // JSON 객체를 꺼낼 때 형변환이 필요 : (Map<String, Object>)
        Map<String, Object> kakaoAccount = (Map<String, Object>) attributes.get("kakao_account");
        if (kakaoAccount != null) {
            return (String) kakaoAccount.get("email");
        }
        return null;
    }

    // 사용자의 이름 (카카오는 nickname)
    @Override
    public String getName() {
        // kakao_account -> profile -> nickname
        Map<String, Object> kakaoAccount = (Map<String, Object>) attributes.get("kakao_account");
        if (kakaoAccount != null) {
            Map<String, Object> profile = (Map<String, Object>) kakaoAccount.get("profile");
            if (profile != null) {
                return (String) profile.get("nickname");
            }
        }
        return null;
    }

    // 필요시 전체 사용자 정보(JSON)을 반환할 수 있도록 추가
    public Map<String, Object> getAttributes() {
        return attributes;
    }

}
