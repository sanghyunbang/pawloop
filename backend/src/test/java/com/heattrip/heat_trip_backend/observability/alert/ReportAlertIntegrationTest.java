package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.chatweb.ChatReports;
import com.heattrip.heat_trip_backend.moderation.ReportReason;
import com.heattrip.heat_trip_backend.moderation.ReportReceipt;
import com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.reactive.function.client.WebClient;

import javax.sql.DataSource;
import java.time.Instant;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 신고 접수 → 커밋 뒤 비동기 알림의 실측 — 이슈 #707 §7.
 *
 * <p>{@code PushDispatchIntegrationTest} 와 같은 모양이다. 슬랙은 가짜다 — 부르는 순간의 트랜잭션
 * 유무와 {@code report} 행의 가시성을 같이 적는다.
 *
 * <h2>되돌리기 (#21 §4)</h2>
 * <ul>
 *   <li>{@code Reports.file} 의 {@code publishEvent} 를 지우면 — 값·커밋·채팅 검사와 롤백 검사의
 *       대조군이 빨개진다.</li>
 *   <li>리스너의 {@code AFTER_COMMIT} 을 {@code @EventListener} 로 바꾸면 — 커밋·롤백 검사가 빨개진다.</li>
 *   <li>{@code @Async} 를 떼면 — <b>"커밋된 뒤에 보낸다" 가 빨개진다.</b> 이슈 §7 은 검사 4 가
 *       빨개질 거라 봤지만 실측은 달랐다: {@code AFTER_COMMIT} 콜백은 동기화 정리 <b>전</b>에 돌아서
 *       그 안에서는 {@code isActualTransactionActive()} 가 아직 참이고, 그것을 검사 2 가 잡는다.
 *       검사 4 는 {@code try/catch} 가 그대로라 초록이다 — 예외가 호출자에게 안 간다.</li>
 *   <li>{@code try/catch} 만 지우면 — <b>"실패는 세어진다" 가 빨개진다.</b> 이슈 §7 은 "아무것도
 *       안 빨개진다" 고 봤는데, 그건 검사 4 를 '예외가 안 난다' 로 짰을 때 이야기다. 여기 검사 4 는
 *       <b>카운터</b>를 재므로, 예외가 {@code failures.increment()} 를 건너뛰는 순간 빨개진다.
 *       두 변형을 반드시 나눠 돌린다 — 묶으면 어느 쪽이 무엇을 잡는지 모른다.</li>
 * </ul>
 * <p>2026-09-20 실측: M1 → 5 · M2 → 2 · M3a → 1(검사 2) · M3b → 1(검사 4) · M4 → 3.
 */
@SpringBootTest
class ReportAlertIntegrationTest extends AbstractMySqlIntegrationTest {

    @TestConfiguration
    static class Fakes {
        @Bean
        @Primary
        RecordingSlack recordingSlack(DataSource dataSource, ObservabilityProperties props) {
            return new RecordingSlack(new JdbcTemplate(dataSource), props);
        }
    }

    /** 신고 알림만 가로챈다. 부르는 순간의 트랜잭션 유무와 행의 가시성을 같이 적는다. */
    static class RecordingSlack extends SlackNotifier {
        final JdbcTemplate jdbc;
        final List<String> texts = new CopyOnWriteArrayList<>();
        volatile CountDownLatch arrived = new CountDownLatch(1);
        volatile Boolean transactionActiveDuringSend;
        volatile Integer reportRowsVisibleDuringSend;
        volatile boolean fail;

        RecordingSlack(JdbcTemplate jdbc, ObservabilityProperties props) {
            super(WebClient.builder(), props);
            this.jdbc = jdbc;
        }

        void reset() {
            texts.clear();
            arrived = new CountDownLatch(1);
            transactionActiveDuringSend = null;
            reportRowsVisibleDuringSend = null;
            fail = false;
        }

        @Override
        public boolean sendReport(String text) {
            try {
                transactionActiveDuringSend = TransactionSynchronizationManager.isActualTransactionActive();
                long reportId = Long.parseLong(text.substring(text.indexOf('#') + 1, text.indexOf(' ', text.indexOf('#'))));
                reportRowsVisibleDuringSend = jdbc.queryForObject(
                        "select count(*) from report where id = ?", Integer.class, reportId);
                if (fail) {
                    throw new IllegalStateException("슬랙이 죽었다");
                }
                texts.add(text);
                return true;
            } finally {
                arrived.countDown();
            }
        }
    }

    @Autowired private RecordingSlack slack;
    @Autowired private ReportAlertListener listener;
    @Autowired private Reports reports;
    @Autowired private ChatReports chatReports;
    @Autowired private ChatRoomService rooms;
    @Autowired private UserRepository users;
    @Autowired private PlatformTransactionManager txManager;

    private static final AtomicLong SEQUENCE = new AtomicLong();
    private static final Instant WHEN = Instant.parse("2026-09-18T05:03:00Z");

    @BeforeEach
    void setUp() {
        slack.reset();
    }

    // ─────────────────────── ① 값 ───────────────────────

    @Test
    @DisplayName("운영자에게 필요한 값이 실린다 — DB 가 준 report.id 로 단언한다")
    void carriesWhatAnOperatorNeeds() throws Exception {
        ReportReceipt receipt = reports.file(128L, 41L, ReportReason.ABUSE, "연락처 010-1234-5678",
                List.of(post(873L, 41L, "달리는초코", "야 너 진짜 그러지 마라 " + "가".repeat(200))));

        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).as("알림이 10초 안에 불려야 한다").isTrue();
        String text = slack.texts.get(0);
        assertThat(text)
                // 고정 템플릿으로는 통과 못 한다 — 이 번호는 실행마다 다르다.
                .contains("신고 #" + receipt.reportId())
                .contains("abuse")
                .contains("community_post 873")
                .contains("u#41").contains("\"달리는초코\"")
                .contains("신고자 u#128")
                // 처음엔 "있음" 만 싣고 본문은 안 실었다 — 연락처를 적는 자리라서. 그런데 메모는
                // 운영자에게 쓴 글이고 읽을 화면이 따로 없어 "있음" 은 쓸모가 없었다(2026-09-20 첫 신고).
                // 본문과 같은 80자 규칙으로 싣는다. 채널은 운영자만 본다.
                .as("메모 앞부분이 그대로 실린다 — 운영자가 이것만 보고 판단해야 한다")
                .contains("메모   \"연락처 010-1234-5678\"");
        assertThat(text.indexOf("가".repeat(81)))
                .as("커뮤니티 본문은 앞 80자까지다")
                .isEqualTo(-1);
    }

    // ─────────────────────── ② 커밋 뒤 · ③ 롤백이면 안 간다 ───────────────────────

    @Test
    @DisplayName("커밋된 뒤에 보낸다 — 발송 시점에 트랜잭션이 없고 report 행이 다른 연결에서 보인다")
    void sendsAfterCommit() throws Exception {
        reports.file(1L, 2L, ReportReason.SPAM, null, List.of(post(10L, 2L, "누구", "광고")));

        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).isTrue();
        assertThat(slack.transactionActiveDuringSend)
                .as("저장 트랜잭션 안에서 슬랙을 부르면 슬랙 지연이 곧 신고 응답 지연이다")
                .isFalse();
        assertThat(slack.reportRowsVisibleDuringSend)
                .as("커밋 전에 보내면 롤백된 신고의 알림이 나간다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("롤백이면 안 나간다 — 그리고 같은 검사에서 이어지는 정상 신고는 도착한다")
    void nothingGoesOutOnRollback() throws Exception {
        TransactionTemplate tx = new TransactionTemplate(txManager);
        assertThatThrownBy(() -> tx.executeWithoutResult(status -> {
            reports.file(1L, 2L, ReportReason.SPAM, null, List.of(post(11L, 2L, "누구", "롤백될 글")));
            throw new IllegalStateException("바깥 트랜잭션이 뒤집힌다");
        })).isInstanceOf(IllegalStateException.class);

        assertThat(slack.arrived.await(2, TimeUnit.SECONDS))
                .as("롤백된 신고의 알림이 나갔다 — AFTER_COMMIT 이 아니라 @EventListener 다")
                .isFalse();
        assertThat(slack.texts).isEmpty();

        // 대조군 — 이게 없으면 배선이 통째로 죽어도 위 단언은 초록이다.
        slack.reset();
        reports.file(1L, 2L, ReportReason.SPAM, null, List.of(post(12L, 2L, "누구", "정상 글")));
        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).as("정상 신고는 도착해야 한다").isTrue();
        assertThat(slack.texts).singleElement().asString().contains("community_post 12");
    }

    // ─────────────────────── ④ 알림이 실패해도 신고는 남는다 ───────────────────────

    @Test
    @DisplayName("알림이 실패해도 신고는 저장되고, 실패는 세어진다 — '예외가 안 난다' 는 @Async 뒤에서 공짜 초록이다")
    void alertFailureDoesNotBreakFiling() throws Exception {
        slack.fail = true;
        double before = listener.failureCount();

        ReportReceipt receipt = reports.file(1L, 2L, ReportReason.FRAUD, null,
                List.of(post(13L, 2L, "누구", "사기")));

        assertThat(receipt.reportId()).as("접수 자체는 알림과 무관하게 성공한다").isPositive();
        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).isTrue();
        // 실행기 스레드에서 catch 가 도는 순간까지 한 박자 기다린다.
        for (int i = 0; i < 50 && listener.failureCount() == before; i++) {
            Thread.sleep(50);
        }
        assertThat(listener.failureCount()).as("실패가 안 세어지면 켜 놓고 죽어도 아무도 모른다").isEqualTo(before + 1);
    }

    // ─────────────────────── ⑤ 채팅 경로 ───────────────────────

    @Test
    @DisplayName("채팅 신고도 알린다 — 그리고 본문과 이름은 한 글자도 안 실린다")
    void chatReportsAlertWithoutBodyOrName() throws Exception {
        User reporter = signUp("신고하는사람");
        User troll = signUp("가족방의아빠");
        ChatRoomView room = rooms.openRoom("REPORTALERT_TEST",
                "alert-" + System.nanoTime() + "-" + SEQUENCE.incrementAndGet(),
                "알림 테스트방", "FAMILY", reporter.getId());
        rooms.joinByInviteCode(rooms.issueInvite(room.id(), reporter.getId()).code(), troll.getId());
        long seq = rooms.postMessage(room.id(), troll.getId(), troll.getNickname(),
                "은밀한 대화 내용", "text", null).roomSeq();

        ReportReceipt receipt = chatReports.file(room.id(), reporter.getId(), List.of(seq), "abuse", null);

        assertThat(slack.arrived.await(10, TimeUnit.SECONDS))
                .as("ChatReports 에는 @Transactional 이 없어 커밋 경계가 커뮤니티와 다르다 — 그래도 도착해야 한다")
                .isTrue();
        assertThat(slack.texts).singleElement().asString()
                .contains("신고 #" + receipt.reportId())
                .contains("chat_message")
                .contains("(채팅 · 본문은 DB)")
                .doesNotContain("은밀한 대화 내용")
                .doesNotContain("가족방의아빠");
    }

    // ─────────────────────── 지그 ───────────────────────

    private static ReportSnapshotInput post(long postId, Long authorId, String authorName, String body) {
        return ReportSnapshotInput.target(ReportTarget.post(postId), authorId, authorName, "제목", body, WHEN);
    }

    private User signUp(String nickname) {
        return users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("reportalert-%d@example.com".formatted(System.nanoTime()))
                .name(nickname)
                .nickname(nickname)
                .build());
    }
}
