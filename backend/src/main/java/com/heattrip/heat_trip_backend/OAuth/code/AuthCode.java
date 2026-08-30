package com.heattrip.heat_trip_backend.OAuth.code;

import java.time.Instant;

/**
 * 1회용 인가 코드가 붙들고 있는 것. (이슈 #14)
 *
 * <p>코드 자체는 <b>아무 의미가 없는 난수</b>다. 이 레코드가 그 난수에 붙은 사실
 * 전부이고, 서버 메모리 밖으로 나가지 않는다. 코드가 딥링크로 나가고 앱이 그것을
 * 되돌려 주는 동안, 토큰을 만들 재료는 여기 남아 있는다.
 *
 * <p><b>권한(role)은 여기에 없다.</b> 예전에는 발급 시점의 권한을 실어 날랐는데
 * 프로덕션 어디에서도 읽지 않았다 — {@code OAuthCodeExchangeService} 가 교환 시점에
 * {@code users} 행에서 다시 읽는다(발급~교환 사이 60초의 탈퇴·권한 변경을 반영해야 하므로
 * 그쪽이 옳다). 테스트 두 곳만 그 값을 단언해 "코드를 타고 전달된다" 는 인상을 주고
 * 있었다. 값이 틀려도 아무 일이 없는 필드는 초록불을 거짓말시킨다.
 *
 * @param userId   토큰의 subject 가 될 users.id
 * @param provider 이 코드를 만든 소셜 공급자. 교환 요청의 경로 변수와 대조한다
 * @param state    앱이 인증 시작 때 만들어 보낸 난수. 교환 요청의 값과 대조한다
 * @param isNew    이번 인증으로 계정이 새로 생겼는가 (계약 {@code AuthTokens.isNew})
 * @param expiresAt 이 시각 <b>이후</b>로는 교환할 수 없다
 */
public record AuthCode(Long userId,
                       String provider,
                       String state,
                       boolean isNew,
                       Instant expiresAt) {
}
