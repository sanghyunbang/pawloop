package com.heattrip.heat_trip_backend.user.dto;

/**
 * {@code POST /auth/token/refresh} 의 요청 본문. (이슈 #9)
 *
 * <p>계약이 본문으로 선언했으므로 헤더나 쿠키가 아니다. {@code Authorization: Bearer <RT>} 로
 * 받으면 액세스 토큰과 헤더를 공유해 {@code JWTAuthenticationFilter} 가 RT 를 JWT 로 파싱하려
 * 들고, 쿠키는 CSRF 처리를 끌어들이면서 stateless 정책과 어긋난다.
 *
 * <p>{@code null}·공백 검증을 여기(빈 검증 애너테이션)에 두지 않는 이유: 그러면 400 이 되는데
 * 계약은 유효하지 않은 RT 를 <b>본문 없는 401</b> 로 선언했다. 검증은
 * {@code RefreshTokenService.rotate} 안에서 {@code UnauthenticatedException} 으로 떨어뜨린다.
 */
public class RefreshTokenRequest {

    private String refreshToken;

    public String getRefreshToken() {
        return refreshToken;
    }

    public void setRefreshToken(String refreshToken) {
        this.refreshToken = refreshToken;
    }
}
