package com.heattrip.heat_trip_backend.OAuth.user;

import org.springframework.security.oauth2.core.oidc.OidcIdToken;
import org.springframework.security.oauth2.core.oidc.OidcUserInfo;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;

import java.util.Map;

/**
 * OpenID Connect 로 들어온 사용자 — {@link CustomOAuth2User} 에 id_token 을 얹은 것. 이슈 #301.
 *
 * <p>Spring Security 는 등록의 scope 에 {@code openid} 가 있으면 OIDC 경로를 타고, 그 경로의
 * 사용자 서비스는 {@link OidcUser} 를 돌려줘야 한다. 그런데 {@code OAuth2SuccessHandler} 는
 * principal 을 {@link CustomOAuth2User} 로 캐스팅해 {@code users.id} 와 {@code isNew} 를 읽는다.
 * 둘을 동시에 만족하는 것이 이 클래스다 — 카카오·구글 경로는 이 클래스를 모른다.
 */
public class CustomOidcUser extends CustomOAuth2User implements OidcUser {

    private final OidcIdToken idToken;
    private final OidcUserInfo userInfo;

    public CustomOidcUser(OAuth2UserInfo userInfo,
                          OidcIdToken idToken,
                          OidcUserInfo oidcUserInfo,
                          Long userId,
                          String role,
                          boolean isNew) {
        super(userInfo, idToken.getClaims(), userId, role, isNew);
        this.idToken = idToken;
        this.userInfo = oidcUserInfo;
    }

    @Override
    public Map<String, Object> getClaims() {
        return getAttributes();
    }

    @Override
    public OidcUserInfo getUserInfo() {
        return userInfo;
    }

    @Override
    public OidcIdToken getIdToken() {
        return idToken;
    }
}
