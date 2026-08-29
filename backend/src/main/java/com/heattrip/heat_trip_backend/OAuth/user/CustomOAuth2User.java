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

    /** DB 에 role 컬럼이 없던 시절의 하드코딩 값. 이제는 fallback 으로만 쓴다. */
    private static final String DEFAULT_ROLE = "ROLE_USER";

    // OAuth2UserInfo는 Google/Kakao/Naver 정보를 통일시킨 인터페이스
    private final OAuth2UserInfo userInfo;

    // 원본 attributes: 소셜 제공자로부터 받은 사용자 정보 원본
    private final Map<String, Object> attributes;

    /** users 테이블 PK. 소셜 응답이 아니라 우리 DB 가 정한 값이다. */
    private final Long userId;

    /** DB 의 role 컬럼 값 (예: ROLE_USER). */
    private final String role;

    /**
     * 이번 인증으로 계정이 <b>새로 만들어졌는지</b>.
     *
     * <p>계약(openapi.yaml)의 {@code AuthTokens.isNew} 로 나가는 <b>로그인 1회성 이벤트 속성</b>이다.
     * 사용자 프로필의 영속 속성이 아니라서 {@code User} 스키마에는 없다 — 그래서 여기 있다.
     * true 면 앱이 온보딩(반려견 프로필 등록)으로 분기한다. (이슈 #7)
     */
    private final boolean isNew;

    /**
     * 생성자: 통합 사용자 정보와 attributes를 저장
     *
     * <p>DB 를 거치지 않는 호출부(테스트 지그 등)를 위한 축약형. 신규 가입이 아님을 뜻한다.
     */
    public CustomOAuth2User(OAuth2UserInfo userInfo, Map<String, Object> attributes) {
        this(userInfo, attributes, null, DEFAULT_ROLE, false);
    }

    public CustomOAuth2User(OAuth2UserInfo userInfo,
                            Map<String, Object> attributes,
                            Long userId,
                            String role,
                            boolean isNew) {
        this.userInfo = userInfo;
        this.attributes = attributes;
        this.userId = userId;
        this.role = (role == null || role.isBlank()) ? DEFAULT_ROLE : role;
        this.isNew = isNew;
    }

    /**
     * getName()
     * Spring Security에서 사용자 식별용으로 사용하는 메서드
     * provider + "_" + providerId 형식으로 통일 (예: kakao_123456)
     *
     * <p><b>이 값은 JWT subject 가 아니다.</b> 토큰의 {@code sub} 는 {@link #getUserId()}(= users.id)다.
     * 예전에는 {@code OAuth2SuccessHandler} 가 {@code authentication.getName()} 을 그대로 subject 로
     * 썼고, 소비처가 그 값을 이메일로 해석해 모든 소셜 계정에서 {@code /auth/me} 가 400 이었다. (이슈 #5)
     */
    @Override
    public String getName() {
        // 이 값은 provider_providerId, 즉 소셜 ID 다. 어떤 레벨로도 로그에 남기지 않는다. (이슈 #6)
        return userInfo.getProvider() + "_" + userInfo.getProviderId();
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
     * 사용자의 권한 정보를 반환. DB 의 role 컬럼을 그대로 쓴다(이슈 #7 이전에는 상수였다).
     */
    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return Collections.singleton(new SimpleGrantedAuthority(role));
    }

    /**
     * getUserInfo()
     * 커스텀 OAuth2UserInfo 객체 반환 (provider, id, email 등에 접근 가능)
     */
    public OAuth2UserInfo getUserInfo() {
        return userInfo;
    }

    /** users.id. 축약 생성자로 만들었으면 null. */
    public Long getUserId() {
        return userId;
    }

    public String getRole() {
        return role;
    }

    /** 이번 로그인에서 계정이 새로 생성되었으면 true. */
    public boolean isNew() {
        return isNew;
    }
}
