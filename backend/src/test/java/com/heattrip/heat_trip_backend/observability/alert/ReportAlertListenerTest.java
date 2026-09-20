package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.moderation.ReportFiled;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;

import io.micrometer.core.instrument.simple.SimpleMeterRegistry;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.reactive.function.client.WebClient;

import java.time.Instant;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 알림 본문에 <b>무엇이 실리고 무엇이 안 실리는가</b> — 이슈 #707 §4·§7.
 *
 * <p>스프링을 안 띄운다. 재려는 것이 "문자열을 어떻게 짓는가" 하나라, 컨텍스트를 띄우면 그 판정이
 * 다른 설정에 섞인다({@code MailerSelectionTest} 와 같은 판단).
 *
 * <p>안 실리는 것을 재는 검사가 실리는 것을 재는 검사보다 많다. 그게 이 화면의 요점이다 — 알림
 * 채널에 실린 것은 신고자·작성자 양쪽에게 <b>돌아갈 수 있는</b> 것이다.
 */
class ReportAlertListenerTest {

    private static final Instant FILED = Instant.parse("2026-09-18T05:03:00Z"); // KST 14:03

    // ─────────────────────── 실리는 것 ───────────────────────

    @Test
    @DisplayName("운영자가 DB 질의를 짤 수 있는 좌표가 다 실린다 — 번호·사유·대상·작성자·신고자·시각·메모 유무")
    void carriesTheCoordinatesAnOperatorNeeds() {
        String text = ReportAlertListener.format(new ReportFiled(
                1204L, "abuse", 128L, 41L, true, FILED,
                List.of(new ReportFiled.Target("community_post", 873L, 41L, "달리는초코",
                        "야 너 진짜 그러지 마라"))));

        assertThat(text)
                .contains("신고 #1204")
                .contains("abuse")
                .contains("community_post 873")
                .contains("u#41")
                .contains("\"달리는초코\"")
                .contains("신고자 u#128")
                .as("저장은 UTC 지만 운영자는 한국에 있다 — KST 로 보여야 시각을 두 번 계산하지 않는다")
                .contains("2026-09-18 14:03 KST")
                .contains("메모   있음");
    }

    @Test
    @DisplayName("탈퇴한 사람의 글이면 작성자 자리에 '탈퇴' 라고 적는다 — 빈칸이면 버그로 읽힌다")
    void aDeletedAuthorIsSaidSo() {
        String text = ReportAlertListener.format(new ReportFiled(
                7L, "spam", 9L, null, false, FILED,
                List.of(new ReportFiled.Target("community_comment", 55L, null, null, "광고"))));

        assertThat(text).contains("(글쓴이 탈퇴)").contains("메모   없음");
    }

    // ─────────────────────── 안 실리는 것 ───────────────────────

    @Test
    @DisplayName("채팅이면 본문도 작성자 이름도 안 실린다 — 사적 대화는 알림 채널에 한 글자도 안 간다")
    void chatCarriesNeitherBodyNorName() {
        // 사건 자체가 채팅이면 body·name 을 null 로 든다(Reports 가 그렇게 만든다). 그런데 누가
        // 실수로 값을 넣어 보내도 본문 줄은 채팅에서 그려지지 않아야 한다 — 두 겹으로 막는다.
        String text = ReportAlertListener.format(new ReportFiled(
                31L, "sexual", 5L, 6L, false, FILED,
                List.of(new ReportFiled.Target("chat_message", 900L, 6L, "가족방의 아빠", "은밀한 말"))));

        assertThat(text)
                .contains("chat_message 900")
                .contains("(채팅 · 본문은 DB)")
                .doesNotContain("은밀한 말")
                .doesNotContain("가족방의 아빠")
                .doesNotContain("본문   ");
    }

    @Test
    @DisplayName("커뮤니티 본문은 앞 80자까지다 — 상수가 곧 규칙이라 여기서 못 박는다")
    void communityBodyIsCappedAtEightyCharacters() {
        String longBody = "가".repeat(300);

        String preview = ReportFiled.preview(longBody);

        assertThat(ReportFiled.BODY_PREVIEW_LENGTH).isEqualTo(80);
        assertThat(preview).hasSize(80 + 1).endsWith("…");
        assertThat(ReportFiled.preview("짧은 글")).isEqualTo("짧은 글");
        assertThat(ReportFiled.preview("줄\n바꿈")).as("여러 줄이면 슬랙에서 한 줄로 보이게").isEqualTo("줄 바꿈");
        assertThat(ReportFiled.preview(null)).isNull();
    }

    @Test
    @DisplayName("신고자는 id 뿐이다 — 이름까지 실으면 알림 채널이 보복의 재료가 된다")
    void theReporterIsOnlyAnId() {
        // ReportFiled 에 신고자 이름을 넣을 자리 자체가 없다. 그 사실을 여기서 기록한다.
        assertThat(ReportFiled.class.getRecordComponents())
                .extracting(java.lang.reflect.RecordComponent::getName)
                .doesNotContain("reporterName", "memo");
    }

    // ─────────────────────── 실패는 센다 ───────────────────────

    @Test
    @DisplayName("보내기가 거짓을 돌려주거나 던지면 실패로 센다 — @Async 뒤에서는 세는 것만이 보이는 신호다")
    void failuresAreCounted() {
        AtomicReference<String> mode = new AtomicReference<>("false");
        SlackNotifier stub = new SlackNotifier(WebClient.builder(), new ObservabilityProperties()) {
            @Override
            public boolean sendReport(String text) {
                if ("throw".equals(mode.get())) {
                    throw new IllegalStateException("슬랙이 500");
                }
                return "true".equals(mode.get());
            }
        };
        ReportAlertListener listener = new ReportAlertListener(stub, new SimpleMeterRegistry());
        ReportFiled event = new ReportFiled(1L, "other", 2L, 3L, false, FILED,
                List.of(new ReportFiled.Target("community_post", 4L, 3L, "누구", "본문")));

        listener.onReportFiled(event);            // 거짓 → 1
        mode.set("throw");
        listener.onReportFiled(event);            // 던짐 → 2 (던지지 않고 삼킨다)
        mode.set("true");
        listener.onReportFiled(event);            // 성공 → 그대로 2

        assertThat(listener.failureCount()).isEqualTo(2.0);
    }
}
