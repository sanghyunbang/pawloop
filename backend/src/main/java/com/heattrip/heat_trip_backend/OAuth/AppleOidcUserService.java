package com.heattrip.heat_trip_backend.OAuth;

import com.heattrip.heat_trip_backend.OAuth.service.CustomOAuth2UserService;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOidcUser;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.oauth2.client.oidc.userinfo.OidcUserRequest;
import org.springframework.security.oauth2.client.oidc.userinfo.OidcUserService;
import org.springframework.security.oauth2.client.userinfo.OAuth2UserService;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;
import org.springframework.stereotype.Service;

/**
 * OpenID Connect 경로의 사용자 서비스 — Apple 이 지난다. 이슈 #301.
 *
 * <p>Spring Security 는 등록의 scope 에 {@code openid} 가 있으면 {@link CustomOAuth2UserService}
 * 가 아니라 이쪽을 부른다. Apple 은 사용자 정보 엔드포인트가 없어 {@link OidcUserService} 가
 * <b>id_token 의 클레임만으로</b> 사용자를 만든다({@code user-info-uri} 가 비어 있으면 부르지 않는다).
 * 그 클레임을 {@code OAuth2UserInfo} 로 옮겨 카카오·구글과 <b>같은 upsert</b>를 지난다 —
 * 가입·이메일 충돌·닉네임 규칙이 두 벌이 되지 않게.
 *
 * <p>돌려주는 것은 {@link CustomOidcUser} 다. {@code OAuth2SuccessHandler} 가 principal 을
 * {@link CustomOAuth2User} 로 읽고, Spring 은 {@link OidcUser} 를 요구한다 — 둘 다인 클래스다.
 *
 * <p>{@code OAuth} 모듈의 <b>루트 패키지</b>에 있는 이유: {@code config.SecurityConfig} 가 이 빈을
 * 배선한다. 하위 패키지({@code OAuth.service})에 두면 모듈 경계 위반이 셋 는다(Modulith 기준선 #109).
 */
@Service
public class AppleOidcUserService implements OAuth2UserService<OidcUserRequest, OidcUser> {

    private static final Logger log = LoggerFactory.getLogger(AppleOidcUserService.class);

    private final OidcUserService delegate = new OidcUserService();
    private final CustomOAuth2UserService users;

    public AppleOidcUserService(CustomOAuth2UserService users) {
        this.users = users;
    }

    @Override
    public OidcUser loadUser(OidcUserRequest request) throws OAuth2AuthenticationException {
        OidcUser oidcUser = delegate.loadUser(request);

        String registrationId = request.getClientRegistration().getRegistrationId();
        OAuth2UserInfo info = CustomOAuth2UserService.toUserInfo(registrationId, oidcUser.getClaims());

        // 소셜 ID 도 이메일도 남기지 않는다. 공급자 이름만. (이슈 #6)
        log.info("[OAuth2 로그인] provider: {} (oidc)", info.getProvider());

        CustomOAuth2User principal = users.upsertUser(info, oidcUser.getClaims());
        return new CustomOidcUser(info, oidcUser.getIdToken(), oidcUser.getUserInfo(),
                principal.getUserId(), principal.getRole(), principal.isNew());
    }
}
