package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.moderation.UserBlocked;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;

import java.lang.reflect.RecordComponent;
import java.time.Instant;
import java.util.Arrays;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 차단 알림 본문에 <b>무엇이 실리고 무엇이 안 실리는가</b> — 애플 지침 1.2 ("차단하면 개발자에게도 알린다").
 *
 * <p>{@link ReportAlertListenerTest} 와 같은 판단으로 스프링을 안 띄운다. 재려는 것이 "문자열을 어떻게
 * 짓는가" 와 "실패를 세는가" 둘이다.
 */
class BlockAlertListenerTest {

    private static final Instant BLOCKED = Instant.parse("2026-10-12T05:03:00Z"); // KST 14:03

    @Test
    @DisplayName("운영자가 DB 를 열 좌표가 다 실린다 — 차단 번호 · 차단당한 사람 · 차단한 사람 · KST 시각")
    void carriesTheCoordinatesAnOperatorNeeds() {
        String text = BlockAlertListener.format(new UserBlocked(57L, 128L, 41L, BLOCKED));

        assertThat(text)
                .as("user_block.id — 운영자가 DB 에서 그 행을 바로 찾는 좌표다")
                .contains("차단 #57")
                .contains("차단당한 사람 u#41")
                .contains("차단한 사람   u#128")
                .as("저장은 UTC 지만 운영자는 한국에 있다 — KST 로 보여야 시각을 두 번 계산하지 않는다")
                .contains("2026-10-12 14:03 KST");
        assertThat(text.lines().findFirst().orElseThrow())
                .as("알림 미리보기는 첫 줄만 보인다 — 누가 누구를 차단했는지가 첫 줄에 있어야 한다")
                .contains("u#128 → u#41");
    }

    @Test
    @DisplayName("차단한 사람과 차단당한 사람을 바꿔 적지 않는다 — 운영자가 거꾸로 조치하면 피해자를 내보낸다")
    void theDirectionIsNotSwapped() {
        String text = BlockAlertListener.format(new UserBlocked(1L, 7L, 9L, BLOCKED));

        assertThat(text).contains("차단당한 사람 u#9").contains("차단한 사람   u#7").contains("u#7 → u#9");
        assertThat(text).doesNotContain("차단당한 사람 u#7").doesNotContain("u#9 → u#7");
    }

    @Test
    @DisplayName("이름도 본문도 실을 자리가 없다 — id 뿐이다")
    void carriesNoNamesAndNoBody() {
        // 사건 record 에 이름·본문 자리가 없다는 사실을 기록한다. 자리가 생기는 날 이 검사가 먼저 묻는다.
        assertThat(Arrays.stream(UserBlocked.class.getRecordComponents()).map(RecordComponent::getName))
                .containsExactly("blockId", "blockerUserId", "blockedUserId", "blockedAt");
    }

    @Test
    @DisplayName("보내기가 거짓을 돌려주거나 던지면 실패로 센다 — @Async 뒤에서는 세는 것만이 보이는 신호다")
    void failuresAreCounted() {
        AtomicReference<String> mode = new AtomicReference<>("false");
        SlackNotifier stub = new SlackNotifier(WebClient.builder(), new ObservabilityProperties()) {
            @Override
            public boolean sendBlock(String text) {
                if ("throw".equals(mode.get())) {
                    throw new IllegalStateException("슬랙이 500");
                }
                return "true".equals(mode.get());
            }
        };
        BlockAlertListener listener = new BlockAlertListener(stub, new SimpleMeterRegistry());
        UserBlocked event = new UserBlocked(1L, 2L, 3L, BLOCKED);

        listener.onUserBlocked(event);            // 거짓 → 1
        mode.set("throw");
        listener.onUserBlocked(event);            // 던짐 → 2 (던지지 않고 삼킨다)
        mode.set("true");
        listener.onUserBlocked(event);            // 성공 → 그대로 2

        assertThat(listener.failureCount()).isEqualTo(2.0);
    }

    @Test
    @DisplayName("웹훅이 비어 있으면 sendBlock 은 거짓이다 — 슬랙이 꺼진 환경에서 던지지 않는다")
    void anEmptyWebhookIsFalseNotAnException() {
        SlackNotifier real = new SlackNotifier(WebClient.builder(), new ObservabilityProperties());

        assertThat(real.sendBlock("차단 #1")).isFalse();
    }
}
