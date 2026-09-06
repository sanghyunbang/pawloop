package com.heattrip.heat_trip_backend.push;

import com.heattrip.heat_trip_backend.push.config.PushConfig;
import com.heattrip.heat_trip_backend.push.fcm.FcmClient;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 키가 없거나 자리표시자거나 깨져 있으면 발송만 꺼지고 부팅은 된다 — #301 의 Apple 키와 같은 방식 (이슈 #83).
 */
class PushConfigTest {

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
    @DisplayName("없는 파일 경로도 같다 — 경고 한 줄과 꺼진 발송")
    void missingFileMeansOff() {
        PushProperties properties = new PushProperties();
        properties.getFirebase().setCredentialsFile("/definitely/not/here/service-account.json");

        assertThat(new PushConfig().fcmClient(properties).isLive()).isFalse();
    }
}
