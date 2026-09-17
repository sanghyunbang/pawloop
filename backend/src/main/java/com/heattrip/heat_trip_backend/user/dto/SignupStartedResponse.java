package com.heattrip.heat_trip_backend.user.dto;

/**
 * {@code POST /auth/signup} 과 {@code /auth/signup/resend} 의 응답 — 이슈 #635.
 *
 * <p><b>계정이 생겼다는 뜻이 아니다.</b> 인증 코드를 보냈다는 뜻이고, 계정은
 * {@code /auth/signup/verify} 에서 생긴다. 그래서 201 이 아니라 <b>202 Accepted</b> 다.
 *
 * <p>{@code mailSent} 가 거짓이면 <b>대기 행은 이미 만들어져 있고 메일만 못 나간 것</b>이다.
 * 앱은 "메일이 안 갔어요 · 다시 보내기" 를 말하면 되고, 사용자는 처음부터 다시 할 필요가
 * 없다. 발송 자격이 없는 환경에서 조용히 성공한 척하지 않으려고 실어 보낸다.
 *
 * @param mailSent 메일이 실제로 나갔는가
 */
public record SignupStartedResponse(boolean mailSent) {
}
