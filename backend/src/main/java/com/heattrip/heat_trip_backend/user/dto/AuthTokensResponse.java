package com.heattrip.heat_trip_backend.user.dto;

import com.fasterxml.jackson.annotation.JsonInclude;

/**
 * 계약(docs/04-api/openapi.yaml)의 {@code AuthTokens} 스키마 그대로의 응답 본문.
 *
 * <p>쓰이는 곳은 셋이다.
 * <ul>
 *   <li>{@code POST /auth/login} — 다섯 필드 전부. {@code isNew} 는 항상 {@code false} 다
 *       (이미 있는 계정으로 들어오는 경로라 "이번에 생성됐는가"의 답이 정해져 있다).</li>
 *   <li>{@code POST /auth/token/refresh} — {@code accessToken}·{@code refreshToken}·
 *       {@code expiresIn} 셋뿐. {@code isNew}·{@code user} 는 {@code null} 이라 <b>JSON 에서
 *       아예 빠진다</b>({@link JsonInclude}). 갱신에 "새로 가입했는가"는 의미가 없고,
 *       계약도 그 둘을 선택 필드로 선언한다. #9 가 만든 그 응답 모양은 여기서 바뀌지 않는다.</li>
 *   <li>계약이 선언한 {@code POST /auth/oauth/{provider}/callback}(미구현, #14)의 목표 모양.</li>
 * </ul>
 *
 * <p><b>{@code isNew} 가 {@code Boolean} 인 것은 의도다.</b> {@code boolean} 이면 갱신 응답에
 * {@code "isNew": false} 가 섞여 나가는데, 그건 "이번 갱신으로 계정이 생기지 않았다"는 참인
 * 문장이 아니라 <b>물어본 적 없는 질문에 대한 답</b>이다. 앱이 그 값으로 온보딩 분기를 하면
 * 갱신마다 판단 근거가 하나 늘어난다.
 *
 * <p>{@code user} 로 {@link UserResponse} 를 그대로 쓰는 이유: 계약의 {@code AuthTokens.user}
 * 는 {@code $ref: User} 이고, {@code GET /auth/me} 의 200 도 같은 {@code User} 다. 인증 응답
 * 전용 {@code UserDto} 를 따로 두면 같은 스키마의 사본이 둘이 되고, 한쪽만 낡는다.
 *
 * @param accessToken  액세스 토큰(JWT)
 * @param refreshToken refresh 토큰 <b>원문</b>. 서버에는 SHA-256 해시만 남는다
 * @param expiresIn    accessToken 이 만료되기까지 남은 초
 * @param isNew        이번 인증으로 계정이 새로 생성됐으면 true. 의미가 없는 응답에서는 null
 * @param user         계약의 {@code User}. 의미가 없는 응답에서는 null
 */
@JsonInclude(JsonInclude.Include.NON_NULL)
public record AuthTokensResponse(
        String accessToken,
        String refreshToken,
        long expiresIn,
        Boolean isNew,
        UserResponse user) {

    /**
     * 갱신 응답 — {@code isNew}·{@code user} 없이.
     *
     * <p>{@code RefreshTokenService.rotate} 가 쓴다. 생성자를 따로 두는 이유는 그 자리에서
     * {@code null, null} 을 적으면 "빠뜨린 것"과 "일부러 뺀 것"이 구별되지 않기 때문이다.
     */
    public AuthTokensResponse(String accessToken, String refreshToken, long expiresIn) {
        this(accessToken, refreshToken, expiresIn, null, null);
    }
}
