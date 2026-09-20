package com.heattrip.heat_trip_backend.push;

import com.google.firebase.FirebaseApp;
import com.heattrip.heat_trip_backend.push.config.PushConfig;
import com.heattrip.heat_trip_backend.push.fcm.FcmClient;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 키가 없거나 자리표시자거나 깨져 있으면 발송만 꺼지고 부팅은 된다 — #301 의 Apple 키와 같은 방식 (이슈 #83).
 */
class PushConfigTest {

    /**
     * 여기서 만들어진 Firebase 앱을 전부 지운다. {@code PushConfig.firebaseApp} 은 같은 이름의 앱이
     * 있으면 키를 읽지 않고 그것을 돌려주므로(테스트 컨텍스트 둘 이상 대비), 안 지우면 "못 읽는 키" 검사가
     * 살아 있는 클라이언트를 받아 빨간불이 된다(2026-09-21 실측). 이 JVM 의 다른 검사는 Firebase 앱을
     * 만들지 않는다(테스트 프로필은 키가 비어 있어 {@code NoopFcmClient}) — 그래서 이름을 안 가리고 다 지운다.
     */
    @AfterEach
    void deleteAppsMadeHere() {
        for (FirebaseApp app : java.util.List.copyOf(FirebaseApp.getApps())) {
            app.delete();
        }
    }

    @Test
    @DisplayName("키가 비어 있으면 발송이 꺼진 클라이언트다")
    void blankMeansOff() {
        PushProperties properties = new PushProperties();

        FcmClient client = new PushConfig().fcmClient(properties);

        assertThat(properties.isConfigured()).isFalse();
        assertThat(client.isLive()).isFalse();
    }

    @Test
    @DisplayName(".env.example 의 자리표시자(change-me…)는 키가 아니다")
    void placeholderMeansOff() {
        PushProperties properties = new PushProperties();
        properties.getFirebase().setCredentialsFile("change-me-path-to-service-account.json");

        assertThat(properties.isConfigured()).isFalse();
        assertThat(new PushConfig().fcmClient(properties).isLive()).isFalse();
    }

    @Test
    @DisplayName("키가 있는데 읽을 수 없으면 부팅을 막지 않고 발송만 끈다")
    void unreadableKeyMeansOffNotCrash() {
        PushProperties properties = new PushProperties();
        properties.getFirebase().setCredentialsJson(
                Base64.getEncoder().encodeToString("{\"type\":\"nonsense\"}".getBytes(StandardCharsets.UTF_8)));

        assertThat(properties.isConfigured()).isTrue();
        assertThat(new PushConfig().fcmClient(properties).isLive()).isFalse();
    }

    @Test
    @DisplayName("키 파일의 project_id 가 Firebase 앱에 실린다 — 부팅 로그가 어느 프로젝트로 보내는지 말한다")
    void projectIdComesFromTheKeyFile() throws Exception {
        // 진짜 키가 아니다 — 방금 만든 RSA 키를 서비스 계정 JSON 모양으로 감쌌다. 네트워크는 안 나간다:
        // 앱을 만드는 것과 토큰을 받는 것은 다른 순간이다.
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        KeyPair pair = generator.generateKeyPair();
        String pem = "-----BEGIN PRIVATE KEY-----\n"
                + Base64.getMimeEncoder(64, "\n".getBytes(StandardCharsets.UTF_8))
                        .encodeToString(pair.getPrivate().getEncoded())
                + "\n-----END PRIVATE KEY-----\n";
        String json = "{\"type\":\"service_account\",\"project_id\":\"pawloop-test\","
                + "\"private_key_id\":\"k1\",\"private_key\":\"" + pem.replace("\n", "\\n") + "\","
                + "\"client_email\":\"push@pawloop-test.iam.gserviceaccount.com\",\"client_id\":\"1\","
                + "\"token_uri\":\"https://oauth2.googleapis.com/token\"}";
        PushProperties properties = new PushProperties();
        properties.getFirebase().setCredentialsJson(
                Base64.getEncoder().encodeToString(json.getBytes(StandardCharsets.UTF_8)));

        FcmClient client = new PushConfig().fcmClient(properties);

        assertThat(client.isLive()).isTrue();
        assertThat(FirebaseApp.getApps())
                .as("키 파일의 project_id 가 앱 옵션에 실려야 부팅 로그가 프로젝트 이름을 찍는다")
                .anySatisfy(app -> assertThat(app.getOptions().getProjectId()).isEqualTo("pawloop-test"));
    }

    @Test
    @DisplayName("없는 파일 경로도 같다 — 경고 한 줄과 꺼진 발송")
    void missingFileMeansOff() {
        PushProperties properties = new PushProperties();
        properties.getFirebase().setCredentialsFile("/definitely/not/here/service-account.json");

        assertThat(new PushConfig().fcmClient(properties).isLive()).isFalse();
    }
}
