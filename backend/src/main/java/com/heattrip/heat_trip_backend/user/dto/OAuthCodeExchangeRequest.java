package com.heattrip.heat_trip_backend.user.dto;

/**
 * {@code POST /auth/oauth/{provider}/callback} 의 요청 본문. (이슈 #14)
 *
 * <p>딥링크로 받은 1회용 {@code code} 와, 앱이 인증 시작 때 만들어 저장해 둔 {@code state} 다.
 *
 * <p>{@code null}·공백 검증을 빈 검증 애너테이션으로 두지 않는 이유는
 * {@link RefreshTokenRequest} 와 같다 — 그러면 400 이 되는데, 계약은 교환 실패를 원인과
 * 무관하게 <b>본문 없는 401</b> 로 선언한다. 검증은 {@code OAuthCodeExchangeService} 안에서
 * {@code UnauthenticatedException} 으로 떨어진다.
 */
public class OAuthCodeExchangeRequest {

    private String code;

    /**
     * 앱이 만든 난수. 옛 앱은 보내지 않으므로 필수가 아니다 — 서버는 코드 발급 시점에
     * 담아 둔 값과만 대조한다(둘 다 없으면 통과).
     */
    private String state;

    /**
     * 계약이 예시로 적고 있는 필드. <b>리다이렉트 대상으로 쓰이지 않는다</b> — 이 시점에는
     * 리다이렉트가 이미 끝났고, 대상은 서버 설정의 허용 목록이 정한다.
     */
    private String redirectUri;

    public String getCode() {
        return code;
    }

    public void setCode(String code) {
        this.code = code;
    }

    public String getState() {
        return state;
    }

    public void setState(String state) {
        this.state = state;
    }

    public String getRedirectUri() {
        return redirectUri;
    }

    public void setRedirectUri(String redirectUri) {
        this.redirectUri = redirectUri;
    }
}
