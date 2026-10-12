package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.moderation.Blocks;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

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
import org.springframework.web.server.ResponseStatusException;

import javax.sql.DataSource;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 차단 → 커밋 뒤 비동기 알림의 실측 — 애플 지침 1.2 ("차단하면 개발자에게도 알린다").
 *
 * <p>{@link ReportAlertIntegrationTest} 와 같은 모양이다. 슬랙은 가짜고, 부르는 순간의 트랜잭션 유무 ·
 * {@code user_block} 행의 가시성 · 도는 스레드를 같이 적는다.
 *
 * <h2>왜 컨텍스트를 하나 더 띄우나 (#21 §5)</h2>
 * <p>가짜 슬랙이 {@code sendBlock} 을 가로채야 하는데, 신고 검사의 가짜는 {@code sendReport} 만 가로채고
 * 그 본문에서 신고 번호를 파싱한다. 둘을 한 가짜에 섞으면 신고 검사가 차단 본문을 신고로 읽을 수 있다.
 * 운영 기본 설정(가짜 없음)에서의 확인은 {@link BlockAlertDefaultConfigIntegrationTest} 가 기존 컨텍스트를
 * 그대로 쓴다.
 *
 * <h2>사용자 행이 없다</h2>
 * <p>{@code user_block} 은 {@code users} 로 FK 를 안 건다(ADR-0011 결정 4 · {@code Block} javadoc).
 * 그래서 id 만 지어 넣는다 — 차단 경로도 대상의 실재를 확인하지 않는다({@code BlockController}).
 *
 * <h2>되돌리기 (#21 §4) — 2026-10-12 실측</h2>
 * <ul>
 *   <li>{@code Blocks.block} 의 {@code publishEvent} 를 지우면 — 이 클래스 5건과 기본 설정 검사 1건이 빨개진다.</li>
 *   <li>{@code AFTER_COMMIT} 을 {@code @EventListener} 로 바꾸면 — <b>"롤백이면 안 나간다" 하나</b>만 빨개진다.
 *       "커밋된 뒤에 보낸다" 는 초록이었다: {@code @Async} 가 그대로라 실행기 스레드가 커밋보다 늦게 돌면
 *       행이 보인다. 그 검사는 경합에 기대므로 이 변형의 증거로 세지 않는다 — 롤백 검사가 결정적이다.</li>
 *   <li>{@code @Async} 를 떼면 — "커밋된 뒤에, 차단 전용 실행기에서" 가 빨개진다(트랜잭션이 아직 활성이고
 *       스레드 이름이 다르다).</li>
 *   <li>실행기를 {@code reportAlertExecutor} 로 바꾸면 — 같은 검사가 스레드 이름으로 빨개진다.</li>
 *   <li>리스너의 {@code try/catch} 를 떼면 — 실패 셈 검사 2건(이 클래스 · 단위)이 빨개진다.</li>
 *   <li>이미 차단한 사람에게도 발행하면 — "다시 안 알린다" 2건(서비스 · HTTP)이 빨개진다.</li>
 * </ul>
 */
@SpringBootTest
class BlockAlertIntegrationTest extends AbstractMySqlIntegrationTest {

    @TestConfiguration
    static class Fakes {
        @Bean
        @Primary
        RecordingSlack recordingBlockSlack(DataSource dataSource, ObservabilityProperties props) {
            return new RecordingSlack(new JdbcTemplate(dataSource), props);
        }
    }

    /** 차단 알림만 가로챈다. 부르는 순간의 트랜잭션 유무 · 행의 가시성 · 스레드 이름을 같이 적는다. */
    static class RecordingSlack extends SlackNotifier {
        final JdbcTemplate jdbc;
        final List<String> texts = new CopyOnWriteArrayList<>();
        volatile CountDownLatch arrived = new CountDownLatch(1);
        volatile Boolean transactionActiveDuringSend;
        volatile Integer blockRowsVisibleDuringSend;
        volatile String threadDuringSend;
        volatile boolean fail;

        RecordingSlack(JdbcTemplate jdbc, ObservabilityProperties props) {
            super(WebClient.builder(), props);
            this.jdbc = jdbc;
        }

        void reset() {
            texts.clear();
            arrived = new CountDownLatch(1);
            transactionActiveDuringSend = null;
            blockRowsVisibleDuringSend = null;
            threadDuringSend = null;
            fail = false;
        }

        @Override
        public boolean sendBlock(String text) {
            try {
                transactionActiveDuringSend = TransactionSynchronizationManager.isActualTransactionActive();
                threadDuringSend = Thread.currentThread().getName();
                long blockId = Long.parseLong(text.substring(text.indexOf('#') + 1, text.indexOf(' ', text.indexOf('#'))));
                blockRowsVisibleDuringSend = jdbc.queryForObject(
                        "select count(*) from user_block where id = ?", Integer.class, blockId);
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
    @Autowired private BlockAlertListener listener;
    @Autowired private Blocks blocks;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private PlatformTransactionManager txManager;

    /**
     * 검사끼리 사람이 겹치지 않게 — {@code UNIQUE (blocker, blocked)} 가 겹치면 두 번째가 "이미 차단" 이 된다.
     * 실제 사용자 id(AUTO_INCREMENT, 작은 수)와도 안 겹치게 멀리서 시작한다. 컨테이너는 실행마다 새것이다.
     */
    private static final AtomicLong PEOPLE = new AtomicLong(9_000_000_000L);

    @BeforeEach
    void setUp() {
        slack.reset();
    }

    // ─────────────────────── ① 값 ───────────────────────

    @Test
    @DisplayName("운영자에게 필요한 값이 실린다 — DB 가 준 user_block.id 와 양쪽 사용자 id")
    void carriesWhatAnOperatorNeeds() throws Exception {
        long blocker = person();
        long blocked = person();

        assertThat(blocks.block(blocker, blocked)).isTrue();

        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).as("알림이 10초 안에 불려야 한다").isTrue();
        long blockId = jdbc.queryForObject(
                "select id from user_block where blocker_user_id = ? and blocked_user_id = ?",
                Long.class, blocker, blocked);
        assertThat(slack.texts).singleElement().asString()
                // 고정 템플릿으로는 통과 못 한다 — 이 번호는 실행마다 다르다.
                .contains("차단 #" + blockId)
                .contains("차단당한 사람 u#" + blocked)
                .contains("차단한 사람   u#" + blocker);
    }

    // ─────────────────────── ② 커밋 뒤 · ③ 롤백이면 안 간다 ───────────────────────

    @Test
    @DisplayName("커밋된 뒤에, 차단 전용 실행기에서 보낸다 — 트랜잭션이 없고 행이 다른 연결에서 보인다")
    void sendsAfterCommitOnItsOwnExecutor() throws Exception {
        blocks.block(person(), person());

        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).isTrue();
        assertThat(slack.transactionActiveDuringSend)
                .as("저장 트랜잭션 안에서 슬랙을 부르면 슬랙 지연이 곧 차단 응답 지연이다")
                .isFalse();
        assertThat(slack.blockRowsVisibleDuringSend)
                .as("커밋 전에 보내면 롤백된 차단의 알림이 나간다")
                .isEqualTo(1);
        assertThat(slack.threadDuringSend)
                .as("""
                        신고 실행기를 같이 쓰면 차단 알림이 신고 알림을 밀어낼 수 있다 — 신고에는 24시간 \
                        처리 약속이 걸려 있다. 차단은 자기 실행기에서 돌아야 한다(AsyncConfig.BLOCK_ALERT_EXECUTOR).""")
                .startsWith("block-alert-");
    }

    @Test
    @DisplayName("롤백이면 안 나간다 — 그리고 같은 검사에서 이어지는 정상 차단은 도착한다")
    void nothingGoesOutOnRollback() throws Exception {
        TransactionTemplate tx = new TransactionTemplate(txManager);
        assertThatThrownBy(() -> tx.executeWithoutResult(status -> {
            blocks.block(person(), person());
            throw new IllegalStateException("바깥 트랜잭션이 뒤집힌다");
        })).isInstanceOf(IllegalStateException.class);

        assertThat(slack.arrived.await(2, TimeUnit.SECONDS))
                .as("롤백된 차단의 알림이 나갔다 — AFTER_COMMIT 이 아니라 @EventListener 다")
                .isFalse();
        assertThat(slack.texts).isEmpty();

        // 대조군 — 이게 없으면 배선이 통째로 죽어도 위 단언은 초록이다.
        slack.reset();
        long blocked = person();
        blocks.block(person(), blocked);
        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).as("정상 차단은 도착해야 한다").isTrue();
        assertThat(slack.texts).singleElement().asString().contains("u#" + blocked);
    }

    // ─────────────────────── ④ 이미 차단했으면 다시 안 알린다 ───────────────────────

    @Test
    @DisplayName("이미 차단해 둔 사람을 또 차단하면 알림이 다시 안 나간다 — 같은 사실을 두 번 알리면 두 사건으로 읽힌다")
    void aRepeatedBlockDoesNotAlertAgain() throws Exception {
        long blocker = person();
        long blocked = person();
        assertThat(blocks.block(blocker, blocked)).isTrue();
        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).isTrue();

        slack.reset();
        assertThat(blocks.block(blocker, blocked)).as("두 번째는 아무것도 안 바꾼다").isFalse();

        assertThat(slack.arrived.await(2, TimeUnit.SECONDS))
                .as("앱이 같은 차단을 두 번 보내도(재시도 · 두 화면) 운영자에게는 한 건이어야 한다")
                .isFalse();
        assertThat(slack.texts).isEmpty();
    }

    @Test
    @DisplayName("자기 자신은 차단할 수 없고, 그때는 알림도 없다")
    void selfBlockIsRejectedWithoutAlert() throws Exception {
        long me = person();

        assertThatThrownBy(() -> blocks.block(me, me)).isInstanceOf(ResponseStatusException.class);

        assertThat(slack.arrived.await(1, TimeUnit.SECONDS)).isFalse();
        assertThat(slack.texts).isEmpty();
    }

    // ─────────────────────── ⑤ 알림이 실패해도 차단은 남는다 ───────────────────────

    @Test
    @DisplayName("알림이 실패해도 차단은 저장되고, 실패는 세어진다 — '예외가 안 난다' 는 @Async 뒤에서 공짜 초록이다")
    void alertFailureDoesNotBreakBlocking() throws Exception {
        slack.fail = true;
        double before = listener.failureCount();
        long blocker = person();
        long blocked = person();

        assertThat(blocks.block(blocker, blocked)).as("차단 자체는 알림과 무관하게 성공한다").isTrue();
        assertThat(blocks.blockedBy(blocker)).contains(blocked);
        assertThat(slack.arrived.await(10, TimeUnit.SECONDS)).isTrue();
        // 실행기 스레드에서 catch 가 도는 순간까지 한 박자 기다린다.
        for (int i = 0; i < 50 && listener.failureCount() == before; i++) {
            Thread.sleep(50);
        }
        assertThat(listener.failureCount()).as("실패가 안 세어지면 켜 놓고 죽어도 아무도 모른다").isEqualTo(before + 1);
    }

    // ─────────────────────── 지그 ───────────────────────

    private static long person() {
        return PEOPLE.incrementAndGet();
    }
}
