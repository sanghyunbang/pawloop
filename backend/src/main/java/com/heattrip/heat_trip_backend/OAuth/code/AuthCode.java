package com.heattrip.heat_trip_backend.OAuth.code;

import java.time.Instant;

/**
 * 1회용 인가 코드가 붙들고 있는 것. (이슈 #14)
 *
 * <p>코드 자체는 <b>아무 의미가 없는 난수</b>다. 이 레코드가 그 난수에 붙은 사실
 * 전부이고, 서버 메모리 밖으로 나가지 않는다. 코드가 딥링크로 나가고 앱이 그것을
 * 되돌려 주는 동안, 토큰을 만들 재료는 여기 남아 있는다.
 *
 * @param userId   토큰의 subject 가 될 users.id
 * @param role     액세스 토큰 클레임에 실을 권한
 * @param provider 이 코드를 만든 소셜 공급자. 교환 요청의 경로 변수와 대조한다
 * @param state    앱이 인증 시작 때 만들어 보낸 난수. 교환 요청의 값과 대조한다
 * @param isNew    이번 인증으로 계정이 새로 생겼는가 (계약 {@code AuthTokens.isNew})
 * @param expiresAt 이 시각 <b>이후</b>로는 교환할 수 없다
 */
public record AuthCode(Long userId,
                       String role,
                       String provider,
                       String state,
                       boolean isNew,
                       Instant expiresAt) {
}
