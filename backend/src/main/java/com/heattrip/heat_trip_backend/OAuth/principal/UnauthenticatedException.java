package com.heattrip.heat_trip_backend.OAuth.principal;

/**
 * 인증 주체를 해석할 수 없다. {@code GlobalExceptionHandler} 가 <b>본문 없는 401</b> 로 매핑한다. (이슈 #5)
 *
 * <p><b>메시지에 식별자·토큰·이메일을 절대 담지 않는다.</b> {@code GlobalExceptionHandler} 는
 * 예외 메시지를 HTTP 응답 본문에 그대로 싣는다 — 담는 순간 그게 유출 경로가 된다. (이슈 #6)
 * 그래서 메시지 인자를 받는 생성자를 두지 않는다.
 */
public class UnauthenticatedException extends RuntimeException {

    public UnauthenticatedException() {
        super("Unauthenticated");
    }
}
