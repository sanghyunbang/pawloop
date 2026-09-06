package com.heattrip.heat_trip_backend.push.fcm;

import com.heattrip.heat_trip_backend.push.PushMessage;

import java.util.ArrayList;
import java.util.List;

/**
 * 토큰 묶음을 FCM 의 상한(한 번에 500)으로 잘라 보내고, 응답에서 죽은 토큰을 가려낸다.
 *
 * <p>SDK 는 {@link FcmTransport} 뒤에 있다 — 이 클래스는 SDK 타입을 모르고, 그래서 가짜 전송으로
 * 결과 해석을 잰다.
 */
public final class FirebaseFcmClient implements FcmClient {

    /** FCM 의 multicast 상한. */
    static final int MAX_TOKENS_PER_CALL = 500;

    private final FcmTransport transport;

    public FirebaseFcmClient(FcmTransport transport) {
        this.transport = transport;
    }

    @Override
    public FcmSendResult send(List<String> tokens, PushMessage message) {
        FcmSendResult total = FcmSendResult.NOTHING;
        for (int from = 0; from < tokens.size(); from += MAX_TOKENS_PER_CALL) {
            List<String> chunk = tokens.subList(from, Math.min(from + MAX_TOKENS_PER_CALL, tokens.size()));
            total = total.plus(summarise(transport.sendEach(chunk, message)));
        }
        return total;
    }

    @Override
    public boolean isLive() {
        return true;
    }

    private static FcmSendResult summarise(List<FcmDelivery> deliveries) {
        int delivered = 0;
        int failed = 0;
        List<String> dead = new ArrayList<>();
        for (FcmDelivery delivery : deliveries) {
            if (delivery.accepted()) {
                delivered++;
            } else {
                failed++;
                if (delivery.tokenIsDead()) {
                    dead.add(delivery.token());
                }
            }
        }
        return new FcmSendResult(delivered, failed, dead);
    }
}
