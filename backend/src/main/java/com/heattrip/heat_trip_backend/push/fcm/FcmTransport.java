package com.heattrip.heat_trip_backend.push.fcm;

import com.heattrip.heat_trip_backend.push.PushMessage;

import java.util.List;

/**
 * Firebase SDK 를 부르는 얇은 층. 토큰은 {@link FirebaseFcmClient} 가 이미 500개 이하로 잘라 준다.
 *
 * <p>인터페이스로 둔 이유는 테스트다 — SDK 의 응답 타입은 밖에서 만들 수 없어서, 결과 해석
 * (죽은 토큰 가리기 · 세기)은 가짜 전송 위에서 잰다({@code FirebaseFcmClientTest}).
 */
public interface FcmTransport {

    List<FcmDelivery> sendEach(List<String> tokens, PushMessage message);
}
