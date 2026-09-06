package com.heattrip.heat_trip_backend.push.fcm;

import com.google.firebase.messaging.AndroidConfig;
import com.google.firebase.messaging.ApnsConfig;
import com.google.firebase.messaging.Aps;
import com.google.firebase.messaging.BatchResponse;
import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.MulticastMessage;
import com.google.firebase.messaging.Notification;
import com.google.firebase.messaging.SendResponse;
import com.heattrip.heat_trip_backend.push.PushMessage;

import java.util.ArrayList;
import java.util.List;

/**
 * firebase-admin 의 {@code sendEachForMulticast} 를 부른다 — HTTP v1 이다. 레거시 서버 키 API 는
 * 2024 년에 끝났다(#83).
 *
 * <p>알림({@code notification})과 데이터를 함께 싣는다 — 앱이 완전히 꺼져 있을 때 시스템이 알림을
 * 그리는 것은 {@code notification} 쪽이고, 앱이 열 자리를 아는 것은 데이터 쪽이다.
 */
public final class FirebaseFcmTransport implements FcmTransport {

    private final FirebaseMessaging messaging;

    public FirebaseFcmTransport(FirebaseMessaging messaging) {
        this.messaging = messaging;
    }

    @Override
    public List<FcmDelivery> sendEach(List<String> tokens, PushMessage message) {
        MulticastMessage multicast = MulticastMessage.builder()
                .addAllTokens(tokens)
                .setNotification(Notification.builder()
                        .setTitle(message.title())
                        .setBody(message.body())
                        .build())
                .putAllData(message.data())
                .setAndroidConfig(AndroidConfig.builder()
                        .setPriority(AndroidConfig.Priority.HIGH)
                        .build())
                .setApnsConfig(ApnsConfig.builder()
                        .setAps(Aps.builder().setSound("default").build())
                        .build())
                .build();
        BatchResponse batch;
        try {
            batch = messaging.sendEachForMulticast(multicast);
        } catch (FirebaseMessagingException e) {
            // 묶음 전체가 거절됐다(인증·네트워크). 토큰 탓이 아니므로 죽은 토큰으로 세지 않는다.
            String code = e.getMessagingErrorCode() == null ? e.getErrorCode().name() : e.getMessagingErrorCode().name();
            List<FcmDelivery> out = new ArrayList<>();
            for (String token : tokens) {
                out.add(new FcmDelivery(token, false, code));
            }
            return out;
        }
        List<FcmDelivery> out = new ArrayList<>(tokens.size());
        List<SendResponse> responses = batch.getResponses();
        for (int i = 0; i < tokens.size(); i++) {
            SendResponse response = responses.get(i);
            if (response.isSuccessful()) {
                out.add(new FcmDelivery(tokens.get(i), true, null));
            } else {
                FirebaseMessagingException failure = response.getException();
                String code = failure == null ? "UNKNOWN"
                        : failure.getMessagingErrorCode() == null ? failure.getErrorCode().name()
                        : failure.getMessagingErrorCode().name();
                out.add(new FcmDelivery(tokens.get(i), false, code));
            }
        }
        return out;
    }
}
