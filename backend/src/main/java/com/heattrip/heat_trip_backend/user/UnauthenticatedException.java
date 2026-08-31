package com.heattrip.heat_trip_backend.user;

/**
 * 인증 주체를 해석할 수 없다. {@code GlobalExceptionHandler} 가 <b>본문 없는 401</b> 로 매핑한다. (이슈 #5)
 *
 * <p><b>메시지에 식별자·토큰·이메일을 절대 담지 않는다.</b> {@code GlobalExceptionHandler} 는
 * 예외 메시지를 HTTP 응답 본문에 그대로 싣는다 — 담는 순간 그게 유출 경로가 된다. (이슈 #6)
 * 그래서 메시지 인자를 받는 생성자를 두지 않는다.
 */
/*
 * 이 타입은 원래 {@code OAuth.principal} 에 있었다. 옮긴 이유는 #107 이다 —
 * {@code user} 의 서비스 둘이 이것을 던지느라 {@code user -> OAuth} 화살표를 만들고 있었고,
 * {@code OAuth} 는 이미 {@code user} 를 부르므로 순환이었다.
 *
 * 401 을 뜻하는 타입을 새로 하나 더 만드는 길도 있었지만 고르지 않았다. 그러면 같은 뜻의
 * 타입이 둘이 되고, 이 저장소는 사본을 싫어한다. 대신 이 하나를 모두가 볼 수 있는 자리로
 * 옮겼다 — {@code user} 패키지 루트는 그 자체로 공개 표면이라 별도 선언이 필요 없다.
 *
 * 던지는 곳: {@code user.service.UserService} · {@code user.service.RefreshTokenService} ·
 * {@code OAuth.code.OAuthCodeExchangeService} · {@code OAuth.principal.CurrentUserArgumentResolver}.
 * 받는 곳: {@code GlobalExceptionHandler} — 본문 없는 401 로 끝난다.
 */
public class UnauthenticatedException extends RuntimeException {

    public UnauthenticatedException() {
        super("Unauthenticated");
    }
}
