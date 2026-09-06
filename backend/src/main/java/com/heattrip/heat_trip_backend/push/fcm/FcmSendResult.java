package com.heattrip.heat_trip_backend.push.fcm;

import java.util.List;

/**
 * 발송 한 번의 결과.
 *
 * @param delivered    FCM 이 받아 준 토큰 수
 * @param failed       받아 주지 않은 토큰 수 — 아래 {@code unregistered} 를 포함한다
 * @param unregistered 죽은 토큰 — FCM 이 "더는 없는 기기" 라고 답한 것. 폐기 대상이다
 */
public record FcmSendResult(int delivered, int failed, List<String> unregistered) {

    public static final FcmSendResult NOTHING = new FcmSendResult(0, 0, List.of());

    public FcmSendResult {
        unregistered = List.copyOf(unregistered);
    }

    public FcmSendResult plus(FcmSendResult other) {
        List<String> dead = new java.util.ArrayList<>(unregistered);
        dead.addAll(other.unregistered);
        return new FcmSendResult(delivered + other.delivered, failed + other.failed, dead);
    }
}
