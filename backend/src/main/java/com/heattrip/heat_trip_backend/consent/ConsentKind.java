package com.heattrip.heat_trip_backend.consent;

/**
 * 동의를 받는 문서 넷 — 이슈 #190. 계약의 {@code ConsentKind} 와 같다.
 *
 * <p>{@code MARKETING} 만 선택이다. 나머지 셋은 필수이지만 <b>그 판정은 여기서 안 한다</b> —
 * 이 모듈은 받은 사실을 있는 그대로 적는다. 철회({@code agreed = false})도 기록이다.
 *
 * <p><b>2026-09-17 정정</b>(#660): 예전에는 "막는 자리는 앱의 동의 화면" 이라고 적혀 있었다.
 * 기록 모듈이 판정하지 않는다는 원칙은 그대로지만, 그 문장은 사실이 아니었다 — <b>토큰이 동의보다
 * 먼저 발급되므로</b> 앱은 막을 수 없다. 앱을 거치지 않고 그 토큰으로 부르면 그만이었다.
 * 지금 막는 자리는 {@code security.ConsentRequiredFilter} 다. 필수 셋의 목록은
 * {@code ConsentService.REQUIRED} 가 든다.
 */
public enum ConsentKind {
    TERMS, PRIVACY, LOCATION, MARKETING
}
