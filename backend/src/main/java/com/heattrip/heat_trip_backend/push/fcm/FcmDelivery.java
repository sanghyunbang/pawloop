package com.heattrip.heat_trip_backend.push.fcm;

/**
 * 토큰 하나의 전달 결과 — 전송 계층({@link FcmTransport})이 SDK 의 응답을 이 모양으로 눕힌다.
 *
 * @param token     보낸 토큰
 * @param accepted  FCM 이 받아 줬는가
 * @param errorCode 거절 이유 — SDK 의 {@code MessagingErrorCode} 이름. 받아 줬으면 {@code null}
 */
public record FcmDelivery(String token, boolean accepted, String errorCode) {

    /** 토큰이 죽었다는 뜻의 오류 — 재시도가 아니라 폐기다. */
    static final java.util.Set<String> DEAD_TOKEN_CODES =
            java.util.Set.of("UNREGISTERED", "INVALID_ARGUMENT", "SENDER_ID_MISMATCH");

    public boolean tokenIsDead() {
        return !accepted && errorCode != null && DEAD_TOKEN_CODES.contains(errorCode);
    }
}
