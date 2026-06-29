package com.heattrip.heat_trip_backend.OAuth.user;

import java.util.Map;

public class NaverOAuth2User implements OAuth2UserInfo {

    private final Map<String, Object> attributes;

    // 생성자 : OAuth2 로그인 후 받아온 전체 속성을 저장

    public NaverOAuth2User(Map<String, Object> attributes) {
        this.attributes = attributes;
    }

    // 소셜 제공자 명 (고정)
    @Override
    public String getProvider() {
        return "naver";
    }

    // 사용자의 고유 ID (네이버는 "id" 필드 사용)
    @Override
    public String getProviderId() {
        Map<String, Object> response = (Map<String, Object>) attributes.get("response");
        if (response != null) {
            return (String) response.get("id");
        }
        return null;
    }
    
    // 네이버 사용자 이메일
    @Override
    public String getEmail() {
        Map<String, Object> response = (Map<String, Object>) attributes.get("response");
        if (response != null) {
            return (String) response.get("email");
        }
        return null;
    }

    // 네이버 사용자 이름
    @Override
    public String getName() {
        Map<String, Object> response = (Map<String, Object>) attributes.get("response");
        if (response != null) {
            return (String) response.get("name"); // 또는 nickname도 가능
        }
        return null;
    }

    // 원본 attribute 전체 반환
    public Map<String, Object> getAttributes() {
        return attributes;
    }
}
