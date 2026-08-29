package com.heattrip.heat_trip_backend.user.dto;

/**
 * {@code POST /auth/token/refresh} 의 200 응답. (이슈 #9)
 *
 * <p>계약(docs/04-api/openapi.yaml)의 {@code AuthTokens} 중 <b>필수 필드</b>
 * ({@code accessToken}·{@code expiresIn})에 회전된 {@code refreshToken} 을 더한 모양이다.
 * 선택 필드인 {@code isNew}·{@code user} 는 싣지 않는다 — {@code isNew} 는 계약이 스스로
 * "로그인 1회성 이벤트 속성"이라고 적었고, 갱신에는 의미가 없다.
 *
 * <p>#10 이 {@code POST /auth/login}·{@code /auth/signup} 의 응답까지 {@code AuthTokens} JSON
 * 으로 옮길 때 이 record 를 통합하거나 개명해도 되는 자리다. 지금 로그인 응답을 JSON 으로
 * 바꾸지 않는 이유는 그 형태 변경이 #10 의 범위이고, 평문 문자열을 파싱하는 앱(#11·#12 소유)을
 * 예고 없이 깨뜨리기 때문이다.
 *
 * @param accessToken  새로 발급한 액세스 토큰(JWT)
 * @param refreshToken 회전된 refresh 토큰 <b>원문</b>. 서버에는 SHA-256 해시만 남는다
 * @param expiresIn    accessToken 이 만료되기까지 남은 초
 */
public record AuthTokensResponse(String accessToken, String refreshToken, long expiresIn) {
}
