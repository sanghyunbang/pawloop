package com.heattrip.heat_trip_backend.OAuth.user;

import java.util.Map;

/**
 * Apple {@code id_token} 의 클레임을 감싼다 — 이슈 #301.
 *
 * <p>Apple 은 사용자 정보 엔드포인트가 <b>없다</b>. 우리가 아는 것은 id_token 의 클레임뿐이다:
 * {@code sub}(고유 ID, 우리 앱에 고정) · {@code email}(사용자가 가리면
 * {@code xxx@privaterelay.appleid.com} 릴레이 주소) · {@code email_verified} · {@code is_private_email}.
 *
 * <p><b>이름은 없다.</b> Apple 은 이름을 <b>첫 인가 응답의 폼 필드</b>({@code user})로 한 번만
 * 주고 그 뒤로는 주지 않는다. 그 필드를 잡으려면 Spring 의 로그인 필터 앞에 필터를 하나 더
 * 둬야 하는데, 그렇게 받은 이름은 두 번째 로그인부터 갱신할 길이 없다. 그래서 안 받는다 —
 * {@code CustomOAuth2UserService} 가 이름이 없으면 "반려인N" 을 초기 닉네임으로 준다.
 */
public class AppleOAuth2User implements OAuth2UserInfo {

    private final Map<String, Object> claims;

    public AppleOAuth2User(Map<String, Object> claims) {
        this.claims = (claims != null) ? claims : Map.of();
    }

    @Override
    public String getProvider() {
        return "apple";
    }

    /** {@code sub} — 이 앱(팀)에 대해 고정된 사용자 ID. 이메일이 바뀌어도 이 값은 그대로다. */
    @Override
    public String getProviderId() {
        return asString(claims.get("sub"));
    }

    /** 릴레이 주소일 수 있다. 사용자가 이메일 공유를 거부하면 없다. */
    @Override
    public String getEmail() {
        return asString(claims.get("email"));
    }

    /** 없다 — 위 javadoc. */
    @Override
    public String getName() {
        return null;
    }

    public Map<String, Object> getAttributes() {
        return claims;
    }

    private static String asString(Object value) {
        return (value instanceof String s && !s.isBlank()) ? s : null;
    }
}
