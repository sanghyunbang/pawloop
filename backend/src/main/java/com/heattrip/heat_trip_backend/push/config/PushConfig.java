package com.heattrip.heat_trip_backend.push.config;

import com.google.auth.oauth2.GoogleCredentials;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.messaging.FirebaseMessaging;
import com.heattrip.heat_trip_backend.push.PushProperties;
import com.heattrip.heat_trip_backend.push.fcm.FcmClient;
import com.heattrip.heat_trip_backend.push.fcm.FirebaseFcmClient;
import com.heattrip.heat_trip_backend.push.fcm.FirebaseFcmTransport;
import com.heattrip.heat_trip_backend.push.fcm.NoopFcmClient;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.io.ByteArrayInputStream;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Base64;

/**
 * 발송 클라이언트를 고른다 — 키가 있으면 Firebase, 없으면 {@link NoopFcmClient} (이슈 #83).
 *
 * <p>키를 읽다 실패하면 <b>부팅을 막지 않는다.</b> 경고를 남기고 발송을 끈다 — 키 파일 하나
 * 때문에 채팅·산책·가족이 전부 안 뜨는 것보다 알림만 안 가는 쪽이 낫다. 운영은 부팅 로그의
 * {@code 푸시 발송이 꺼져 있다} 한 줄로 안다.
 */
@Slf4j
@Configuration
@EnableConfigurationProperties(PushProperties.class)
public class PushConfig {

    static final String FIREBASE_APP_NAME = "pawloop-push";

    @Bean
    public FcmClient fcmClient(PushProperties properties) {
        if (!properties.isConfigured()) {
            log.info("푸시 발송이 꺼져 있다 — app.push.firebase 키가 없다. 토큰 등록·설정·음소거는 그대로 저장된다 (#83)");
            return new NoopFcmClient();
        }
        try {
            FirebaseApp app = firebaseApp(properties.getFirebase());
            log.info("푸시 발송이 켜졌다 — Firebase 프로젝트 {}", app.getOptions().getProjectId());
            return new FirebaseFcmClient(new FirebaseFcmTransport(FirebaseMessaging.getInstance(app)));
        } catch (IOException | RuntimeException e) {
            log.warn("푸시 발송이 꺼져 있다 — Firebase 키를 못 읽었다: {}", e.toString());
            return new NoopFcmClient();
        }
    }

    private static FirebaseApp firebaseApp(PushProperties.Firebase firebase) throws IOException {
        for (FirebaseApp existing : FirebaseApp.getApps()) {
            if (FIREBASE_APP_NAME.equals(existing.getName())) {
                return existing; // 테스트 컨텍스트가 둘 이상 뜰 때 같은 이름으로 두 번 만들면 SDK 가 던진다.
            }
        }
        try (InputStream credentials = open(firebase)) {
            FirebaseOptions options = FirebaseOptions.builder()
                    .setCredentials(GoogleCredentials.fromStream(credentials))
                    .setConnectTimeout(firebase.getConnectTimeoutMs())
                    .setReadTimeout(firebase.getReadTimeoutMs())
                    .build();
            return FirebaseApp.initializeApp(options, FIREBASE_APP_NAME);
        }
    }

    private static InputStream open(PushProperties.Firebase firebase) throws IOException {
        if (firebase.getCredentialsFile() != null && !firebase.getCredentialsFile().isBlank()) {
            return new FileInputStream(firebase.getCredentialsFile().strip());
        }
        return new ByteArrayInputStream(Base64.getDecoder().decode(firebase.getCredentialsJson().strip()));
    }
}
