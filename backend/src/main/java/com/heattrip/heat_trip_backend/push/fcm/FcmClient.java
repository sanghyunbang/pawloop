package com.heattrip.heat_trip_backend.push.fcm;

import com.heattrip.heat_trip_backend.push.PushMessage;

import java.util.List;

/**
 * 기기 토큰 묶음에 알림 하나를 보낸다. 구현은 둘 — Firebase 를 진짜로 부르는 것과, 키가 없을 때
 * 아무것도 안 보내는 것({@link NoopFcmClient}). 어느 쪽인지는 {@code PushConfig} 가 정한다.
 */
public interface FcmClient {

    FcmSendResult send(List<String> tokens, PushMessage message);

    /** 진짜로 나가는가. 키가 없으면 false — 운영 로그와 헬스 판단용이다. */
    boolean isLive();
}
