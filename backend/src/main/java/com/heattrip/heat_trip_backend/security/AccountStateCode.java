package com.heattrip.heat_trip_backend.security;

/**
 * 계정의 상태 때문에 막을 때 쓰는 오류 코드 — 둘 다 403 이다.
 *
 * <h2>세 번째 어휘</h2>
 * <p>{@code GlobalExceptionHandler.codeOf} 의 여덟(HTTP 상태에서 파생)과 {@code ChatErrorCode} 에 이은 세 번째
 * 출처다. 상태에서 파생하지 않는 이유는 채팅 코드와 같다 — 둘 다 403 인데 <b>앱이 보여 줄 화면이 다르다</b>(약관
 * 동의 화면 / 정지 안내 화면). 그리고 둘 다 {@code FORBIDDEN} 과도 다르다. 토큰은 멀쩡하고, 막힌 이유가 그 사람의
 * 계정에 있다.
 *
 * <h2>계약이 이 값을 등재한다</h2>
 * <p>{@code openapi.yaml} 의 {@code Error.code} 는 닫힌 목록이고, {@code AuthContractSpecTest} 가 이 enum 에서 뽑아
 * 대조한다. 예전에는 {@code CONSENT_REQUIRED} 가 필터 안의 문자열로만 있어서 계약에서 빠져 있었다 — 앱은 계약에
 * 없는 코드를 받고 있었다(#718 셋째 조각에서 함께 등재).
 */
public enum AccountStateCode {

    /** 필수 약관에 아직 동의하지 않았다 — {@link ConsentRequiredFilter}. */
    CONSENT_REQUIRED,

    /** 운영 정책 위반으로 정지됐다 — {@link AccountSuspensionFilter}. 계정 삭제와 로그아웃만 열려 있다. */
    ACCOUNT_SUSPENDED
}
