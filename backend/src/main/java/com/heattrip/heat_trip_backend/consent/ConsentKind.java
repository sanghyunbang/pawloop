package com.heattrip.heat_trip_backend.consent;

/**
 * 동의를 받는 문서 넷 — 이슈 #190. 계약의 {@code ConsentKind} 와 같다.
 *
 * <p>{@code MARKETING} 만 선택이다. 나머지 셋은 필수이지만 <b>그 판정은 여기서 안 한다</b> —
 * "필수인데 안 했다" 를 막는 자리는 앱의 동의 화면이고, 서버는 받은 사실을 있는 그대로
 * 적는다. 철회({@code agreed = false})도 기록이다.
 */
public enum ConsentKind {
    TERMS, PRIVACY, LOCATION, MARKETING
}
