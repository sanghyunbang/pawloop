package com.heattrip.heat_trip_backend.push;

import com.heattrip.heat_trip_backend.chat.ChatMessageSender;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import com.heattrip.heat_trip_backend.push.fcm.FcmClient;
import com.heattrip.heat_trip_backend.push.fcm.FcmSendResult;
import com.heattrip.heat_trip_backend.push.repository.DeviceTokenRepository;
import com.heattrip.heat_trip_backend.push.repository.PushPreferenceRepository;
import com.heattrip.heat_trip_backend.push.service.DeviceTokenService;
import com.heattrip.heat_trip_backend.push.service.PushPreferenceService;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.UserService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import javax.sql.DataSource;
import java.time.Duration;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BooleanSupplier;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 메시지 저장 → 커밋 뒤 비동기 발송의 실측 — 이슈 #83 완료 조건 2·3.
 *
 * <h2>무엇을 재는가</h2>
 * <ul>
 *   <li><b>커밋 뒤다</b> — 발송이 불리는 순간 트랜잭션이 없고, 메시지 행이 <b>다른 연결</b>에서 보인다.
 *       {@code PushDispatcher} 의 {@code AFTER_COMMIT} 을 {@code @EventListener} 로 되돌리면 둘 다 뒤집힌다.</li>
 *   <li><b>다른 스레드다</b> — 발송을 문 앞에서 막아 둬도 전송 응답은 바로 돌아온다.
 *       {@code @Async} 를 떼면 전송이 그 문 앞에서 같이 기다린다.</li>
 *   <li><b>수신자 셋을 거른다</b> — 보낸 사람 · 음소거한 사람 · 전체 끈 사람 · 폐기된 토큰.</li>
 *   <li><b>죽은 토큰은 폐기된다</b> — FCM 이 UNREGISTERED 를 주면 {@code revoked_at} 이 찍힌다.</li>
 *   <li><b>로그아웃·탈퇴</b> — 토큰이 폐기·삭제된다(사건은 {@code user} 가 발행한다).</li>
 * </ul>
 *
 * <p>FCM 은 가짜다 — 실기기 도착(완료 조건 1)은 자동화할 수 없다.
 */
@SpringBootTest
class PushDispatchIntegrationTest extends AbstractMySqlIntegrationTest {

    @TestConfiguration
    static class Fakes {
        @Bean
        @Primary
        RecordingFcm recordingFcm(DataSource dataSource) {
            return new RecordingFcm(new JdbcTemplate(dataSource));
        }
    }

    /** 발송을 기록한다. 부르는 순간의 트랜잭션 유무와 메시지 행의 가시성도 같이 적는다. */
    static class RecordingFcm implements FcmClient {
        final JdbcTemplate jdbc;
        final List<List<String>> calls = new CopyOnWriteArrayList<>();
        final List<PushMessage> messages = new CopyOnWriteArrayList<>();
        volatile CountDownLatch arrived = new CountDownLatch(1);
        volatile CountDownLatch gate = new CountDownLatch(0);
        volatile Boolean transactionActiveDuringSend;
        volatile Integer messageRowsVisibleDuringSend;
        volatile Set<String> deadTokens = Set.of();

        RecordingFcm(JdbcTemplate jdbc) {
            this.jdbc = jdbc;
        }

        void reset() {
            calls.clear();
            messages.clear();
            arrived = new CountDownLatch(1);
            gate = new CountDownLatch(0);
            transactionActiveDuringSend = null;
            messageRowsVisibleDuringSend = null;
            deadTokens = Set.of();
        }

        @Override
        public FcmSendResult send(List<String> tokens, PushMessage message) {
            try {
                transactionActiveDuringSend = TransactionSynchronizationManager.isActualTransactionActive();
                long messageId = Long.parseLong(message.data().get("messageId"));
                messageRowsVisibleDuringSend = jdbc.queryForObject(
                        "select count(*) from chat_message where id = ?", Integer.class, messageId);
                try {
                    gate.await(10, TimeUnit.SECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                calls.add(List.copyOf(tokens));
                messages.add(message);
                List<String> dead = tokens.stream().filter(deadTokens::contains).toList();
                return new FcmSendResult(tokens.size() - dead.size(), dead.size(), dead);
            } finally {
                arrived.countDown();
            }
        }

        @Override
        public boolean isLive() {
            return true;
        }
    }

    @Autowired private RecordingFcm fcm;
    @Autowired private ChatRoomService chatRooms;
    @Autowired private ChatMessageSender sender;
    @Autowired private DeviceTokenService deviceTokens;
    @Autowired private DeviceTokenRepository tokenRows;
    @Autowired private PushPreferenceService preferences;
    @Autowired private PushPreferenceRepository preferenceRows;
    @Autowired private UserRepository users;
    @Autowired private UserService userService;

    private static final AtomicLong SEQUENCE = new AtomicLong();

    private User owner;
    private User first;
    private User second;
    private long roomId;

    @BeforeEach
    void setUp() {
        fcm.reset();
        owner = signUp("방장");
        first = signUp("첫째");
        second = signUp("둘째");
        ChatRoomView room = chatRooms.openRoom("FAMILY", "push-" + System.nanoTime() + "-" + SEQUENCE.incrementAndGet(),
                "푸시 테스트방", "FAMILY", owner.getId());
        String code = chatRooms.issueInvite(room.id(), owner.getId()).code();
        chatRooms.joinByInviteCode(code, first.getId());
        chatRooms.joinByInviteCode(code, second.getId());
        roomId = room.id();
        deviceTokens.register(owner.getId(), token("owner"), "android");
        deviceTokens.register(first.getId(), token("first"), "android");
        deviceTokens.register(second.getId(), token("second"), "ios");
    }

    // ─────────────────────────── 커밋 뒤 · 다른 스레드 ───────────────────────────

    @Test
    @DisplayName("메시지가 커밋된 뒤에 보낸다 — 발송 시점에 트랜잭션이 없고 행이 다른 연결에서 보인다")
    void sendsAfterCommit() throws Exception {
        sender.send(roomId, owner.getId(), owner.displayName(), "저녁 산책 갈까요", "text", null);

        assertThat(fcm.arrived.await(10, TimeUnit.SECONDS)).as("발송이 10초 안에 불려야 한다").isTrue();
        assertThat(fcm.transactionActiveDuringSend)
                .as("저장 트랜잭션 안에서 FCM 을 부르면 FCM 지연이 곧 채팅 지연이다 (#83 완료 조건 3)")
                .isFalse();
        assertThat(fcm.messageRowsVisibleDuringSend)
                .as("커밋 전에 보내면 롤백된 메시지의 알림이 나간다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("전송 응답은 발송을 기다리지 않는다 — 문 앞에서 막아 둬도 바로 돌아온다")
    void theResponseDoesNotWaitForDispatch() throws Exception {
        fcm.gate = new CountDownLatch(1);
        long startedAt = System.nanoTime();

        sender.send(roomId, owner.getId(), owner.displayName(), "빨리 답해요", "text", null);

        Duration elapsed = Duration.ofNanos(System.nanoTime() - startedAt);
        assertThat(elapsed)
                .as("발송이 막혀 있는데 전송이 기다렸다면 @Async 가 빠진 것이다")
                .isLessThan(Duration.ofSeconds(3));
        assertThat(fcm.calls).as("아직 문이 닫혀 있으니 발송이 끝났을 리 없다").isEmpty();
        fcm.gate.countDown();
        assertThat(fcm.arrived.await(10, TimeUnit.SECONDS)).isTrue();
        assertThat(fcm.calls).hasSize(1);
    }

    // ─────────────────────────── 수신자 ───────────────────────────

    @Test
    @DisplayName("살아 있는 멤버 전부에게 가고 보낸 사람에게는 안 간다 — 제목은 방 이름, 본문은 이름과 미리보기")
    void everyOtherLiveMemberGetsIt() throws Exception {
        sender.send(roomId, owner.getId(), owner.displayName(), "저녁 산책 갈까요", "text", null);
        assertThat(fcm.arrived.await(10, TimeUnit.SECONDS)).isTrue();

        assertThat(fcm.calls).singleElement().satisfies(tokens ->
                assertThat(tokens).containsExactlyInAnyOrder(token("first"), token("second")));
        PushMessage message = fcm.messages.get(0);
        assertThat(message.title()).isEqualTo("푸시 테스트방");
        assertThat(message.body()).isEqualTo(owner.displayName() + ": 저녁 산책 갈까요");
        assertThat(message.data()).containsEntry("roomId", String.valueOf(roomId)).containsKey("messageId");
    }

    @Test
    @DisplayName("방을 음소거한 사람에게는 그 방의 알림이 안 간다 — 완료 조건 2")
    void mutedMemberIsSkipped() throws Exception {
        assertThat(chatRooms.setMuted(roomId, first.getId(), true)).isTrue();

        sender.send(roomId, owner.getId(), owner.displayName(), "조용히", "text", null);
        assertThat(fcm.arrived.await(10, TimeUnit.SECONDS)).isTrue();

        assertThat(fcm.calls).singleElement().isEqualTo(List.of(token("second")));
    }

    @Test
    @DisplayName("전체 끄기를 한 사람에게는 아무것도 안 간다 — 완료 조건 2")
    void globallyDisabledMemberIsSkipped() throws Exception {
        preferences.setEnabled(second.getId(), false);

        sender.send(roomId, owner.getId(), owner.displayName(), "전체 끔", "text", null);
        assertThat(fcm.arrived.await(10, TimeUnit.SECONDS)).isTrue();

        assertThat(fcm.calls).singleElement().isEqualTo(List.of(token("first")));
    }

    @Test
    @DisplayName("받을 토큰이 하나도 없으면 FCM 을 부르지 않는다")
    void nothingToSendMeansNoCall() throws Exception {
        chatRooms.setMuted(roomId, first.getId(), true);
        preferences.setEnabled(second.getId(), false);

        sender.send(roomId, owner.getId(), owner.displayName(), "아무도 없다", "text", null);

        assertThat(fcm.arrived.await(2, TimeUnit.SECONDS)).as("부르지 않았으니 문이 열리지 않는다").isFalse();
        assertThat(fcm.calls).isEmpty();
    }

    @Test
    @DisplayName("FCM 이 죽었다고 답한 토큰은 폐기되고 산 토큰은 그대로다")
    void unregisteredTokenIsRevoked() throws Exception {
        deviceTokens.register(first.getId(), token("first-old-phone"), "android");
        fcm.deadTokens = Set.of(token("first-old-phone"));

        sender.send(roomId, owner.getId(), owner.displayName(), "옛 폰", "text", null);
        assertThat(fcm.arrived.await(10, TimeUnit.SECONDS)).isTrue();

        waitUntil(() -> tokenRows.findByToken(token("first-old-phone")).map(DeviceToken::getRevokedAt).isPresent());
        assertThat(tokenRows.findByToken(token("first")).orElseThrow().isActive()).isTrue();
    }

    // ─────────────────────────── 로그아웃 · 탈퇴 ───────────────────────────

    @Test
    @DisplayName("로그아웃하면 전 기기의 토큰이 폐기된다 — 행은 남는다")
    void logoutRevokesEveryToken() {
        deviceTokens.register(first.getId(), token("first-tablet"), "android");

        userService.logout(first.getId());

        waitUntil(() -> tokenRows.findByUserId(first.getId()).stream().noneMatch(DeviceToken::isActive));
        assertThat(tokenRows.findByUserId(first.getId())).hasSize(2);
    }

    @Test
    @DisplayName("탈퇴하면 토큰 행과 설정 행이 지워진다 — 개인정보다")
    void deletingTheAccountRemovesTheRows() {
        preferences.setEnabled(second.getId(), false);

        userService.deleteMe(second.getId());

        waitUntil(() -> tokenRows.findByUserId(second.getId()).isEmpty());
        assertThat(preferenceRows.findById(second.getId())).isEmpty();
    }

    // ─────────────────────────── 준비물 ───────────────────────────

    private User signUp(String nickname) {
        return users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("push-%d-%d@example.com".formatted(System.nanoTime(), SEQUENCE.incrementAndGet()))
                .name(nickname)
                .nickname(nickname)
                .build());
    }

    private String token(String device) {
        return "tok-" + roomId + "-" + device;
    }

    private static void waitUntil(BooleanSupplier condition) {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (!condition.getAsBoolean()) {
            if (System.nanoTime() > deadline) {
                throw new AssertionError("10초 안에 조건이 참이 되지 않았다");
            }
            try {
                Thread.sleep(50);
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new AssertionError(e);
            }
        }
    }
}
