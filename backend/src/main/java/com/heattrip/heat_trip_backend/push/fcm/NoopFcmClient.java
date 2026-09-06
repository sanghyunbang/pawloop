package com.heattrip.heat_trip_backend.push.fcm;

import com.heattrip.heat_trip_backend.push.PushMessage;
import lombok.extern.slf4j.Slf4j;

import java.util.List;

/**
 * 키가 없을 때의 발송 — 아무것도 보내지 않고 성공도 실패도 세지 않는다.
 *
 * <p>서버는 뜨고, 토큰 등록·설정·음소거는 저장된다. 키가 들어오는 날 재시작하면
 * {@link FirebaseFcmClient} 로 바뀐다({@code PushConfig}). #301 의 Apple 키와 같은 방식이다.
 */
@Slf4j
public final class NoopFcmClient implements FcmClient {

    @Override
    public FcmSendResult send(List<String> tokens, PushMessage message) {
        log.debug("푸시 발송이 꺼져 있다 — {}개 토큰에 '{}' 을 보내지 않았다", tokens.size(), message.title());
        return FcmSendResult.NOTHING;
    }

    @Override
    public boolean isLive() {
        return false;
    }
}
