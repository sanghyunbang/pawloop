package com.heattrip.heat_trip_backend.OAuth.user;


import java.util.Collection;
import java.util.Collections;
import java.util.Map;

import org.springframework.security.core.GrantedAuthority; // 권한 표현
import org.springframework.security.core.authority.SimpleGrantedAuthority; // 기본 권한 객체 생성
import org.springframework.security.oauth2.core.user.OAuth2User; // OAuth2 인증 사용자 인터페이스

/**
 * CustomOAuth2User
 * 소셜 로그인 후 반환된 사용자 정보를 담는 클래스.
 * OAuth2User를 구현하고, OAuth2UserInfo 기반으로 사용자 정보를 일관되게 관리함.
 */
public class CustomOAuth2User implements OAuth2User {

    // OAuth2UserInfo는 Google/Kakao/Naver 정보를 통일시킨 인터페이스
    private final OAuth2UserInfo userInfo;

    // 원본 attributes: 소셜 제공자로부터 받은 사용자 정보 원본
    private final Map<String, Object> attributes;

    /**
     * 생성자: 통합 사용자 정보와 attributes를 저장
     */
    public CustomOAuth2User(OAuth2UserInfo userInfo, Map<String, Object> attributes) {
        this.userInfo = userInfo;
        this.attributes = attributes;
    }

    /**
     * getName()
     * Spring Security에서 사용자 식별용으로 사용하는 메서드
     * provider + "_" + providerId 형식으로 통일 (예: kakao_123456)
     */
    @Override
    public String getName() {
        String name = userInfo.getProvider() + "_" + userInfo.getProviderId();
        System.out.println("[DEBUG] getName() returns: " + name); // 디버깅 코드 추가[0802]
        return name;
    }

    /**
     * getAttributes()
     * 소셜 로그인으로부터 받은 전체 사용자 정보 (원본 JSON)
     */
    @Override
    public Map<String, Object> getAttributes() {
        return attributes;
    }

    /**
     * getAuthorities()
     * 사용자의 권한 정보를 반환 (여기선 기본적으로 ROLE_USER 부여)
     */
    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return Collections.singleton(new SimpleGrantedAuthority("ROLE_USER"));
    }

    /**
     * getUserInfo()
     * 커스텀 OAuth2UserInfo 객체 반환 (provider, id, email 등에 접근 가능)
     */
    public OAuth2UserInfo getUserInfo() {
        return userInfo;
    }
}