package com.heattrip.heat_trip_backend.push;

import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.group.dto.GroupResponse;
import com.heattrip.heat_trip_backend.group.service.FamilyGroupService;
import com.heattrip.heat_trip_backend.push.fcm.FcmClient;
import com.heattrip.heat_trip_backend.push.fcm.FcmSendResult;
import com.heattrip.heat_trip_backend.push.service.DeviceTokenService;
import com.heattrip.heat_trip_backend.push.service.PushPreferenceService;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleRequest;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleResponse;
import com.heattrip.heat_trip_backend.schedule.dto.ScheduleUpdateRequest;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleKind;
import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;
import com.heattrip.heat_trip_backend.schedule.service.ScheduleService;
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
import org.springframework.transaction.support.TransactionSynchronizationManager;

import java.time.LocalDate;
import java.time.LocalTime;
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.BooleanSupplier;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 배정 푸시의 실측 — 이슈 #735.
 *
 * <ul>
 *   <li>담당이 만든 사람과 다르면 담당자에게 <b>한 번</b>, 커밋 뒤에(발송 시점에 트랜잭션이 없다).</li>
 *   <li>담당이 나면 안 보낸다.</li>
 *   <li>고칠 때 담당이 바뀌면 새 담당에게, 같은 담당이면(제목만 고침) 안 보낸다.</li>
 *   <li>담당자가 전체 끄기를 했거나 토큰이 없으면 FCM 을 부르지 않는다.</li>
 * </ul>
 *
 * <p>FCM 은 가짜다 — 실기기 도착은 앱에 FCM 이 붙는 #83 뒤의 일이다.
 */
@SpringBootTest
class ScheduleAssignedPushIntegrationTest extends AbstractMySqlIntegrationTest {

    @TestConfiguration
    static class Fakes {
        @Bean
        @Primary
        RecordingFcm scheduleRecordingFcm() {
            return new RecordingFcm();
        }
    }

    static class RecordingFcm implements FcmClient {
        final List<List<String>> calls = new CopyOnWriteArrayList<>();
        final List<PushMessage> messages = new CopyOnWriteArrayList<>();
        volatile Boolean transactionActiveDuringSend;

        void reset() {
            calls.clear();
            messages.clear();
            transactionActiveDuringSend = null;
        }

        @Override
        public FcmSendResult send(List<String> tokens, PushMessage message) {
            transactionActiveDuringSend = TransactionSynchronizationManager.isActualTransactionActive();
            calls.add(List.copyOf(tokens));
            messages.add(message);
            return new FcmSendResult(tokens.size(), 0, List.of());
        }

        @Override
        public boolean isLive() {
            return true;
        }
    }

    @Autowired private RecordingFcm fcm;
    @Autowired private ScheduleService schedules;
    @Autowired private FamilyGroupService groups;
    @Autowired private ChatRoomService chatRooms;
    @Autowired private DeviceTokenService deviceTokens;
    @Autowired private PushPreferenceService preferences;
    @Autowired private UserRepository users;

    private static final AtomicLong SEQUENCE = new AtomicLong();

    /** 먼 날짜 — "내일" 같은 상대 표현이 아니라 날짜로 나오게 한다. 상대 표현은 {@code PushMessageTest} 가 잰다. */
    private static final LocalDate FAR = LocalDate.of(2027, 3, 5);

    private User mom;
    private User dad;
    private long groupId;
    private long serial;

    @BeforeEach
    void setUp() {
        fcm.reset();
        serial = SEQUENCE.incrementAndGet();
        mom = signUp("엄마");
        dad = signUp("아빠");
        GroupResponse group = groups.create(mom.getId(), "보리네-" + serial);
        String code = chatRooms.issueInvite(group.roomId(), mom.getId()).code();
        chatRooms.joinByInviteCode(code, dad.getId());
        groupId = group.id();
        deviceTokens.register(mom.getId(), token("mom"), "android");
        deviceTokens.register(dad.getId(), token("dad"), "android");
    }

    @Test
    @DisplayName("담당이 만든 사람과 다르면 담당자에게 한 번 간다 — 커밋 뒤에, 제목은 누가, 본문은 언제 · 무엇")
    void assigneeGetsOnePushAfterCommit() {
        ScheduleResponse created = schedules.create(mom, request("병원 예약", dad.getId()));

        waitUntil(() -> !fcm.messages.isEmpty());
        assertThat(fcm.calls).containsExactly(List.of(token("dad")));
        PushMessage message = fcm.messages.get(0);
        assertThat(message.title()).isEqualTo("엄마님이 일정을 맡겼어요");
        assertThat(message.body()).isEqualTo("3월 5일 10:30 · 병원 예약");
        assertThat(message.data())
                .containsEntry("kind", "schedule.assigned")
                .containsEntry("scheduleId", String.valueOf(created.id()))
                .containsEntry("onDate", "2027-03-05");
        assertThat(fcm.transactionActiveDuringSend)
                .as("커밋 전에 보내면 롤백된 배정의 알림이 나간다")
                .isFalse();
    }

    @Test
    @DisplayName("담당이 나면 안 보낸다 — 내가 나에게 맡긴 것을 알릴 이유가 없다")
    void selfAssignmentIsSilent() throws Exception {
        schedules.create(mom, request("내 병원", mom.getId()));
        schedules.create(mom, request("담당 없음", null));

        settle();
        assertThat(fcm.calls).isEmpty();
    }

    @Test
    @DisplayName("고칠 때 담당이 바뀌면 새 담당에게 · 같은 담당이면(제목만 고침) 안 보낸다")
    void reassignmentNotifiesOnlyWhenTheAssigneeChanges() throws Exception {
        ScheduleResponse created = schedules.create(mom, request("병원 예약", mom.getId()));
        settle();
        assertThat(fcm.calls).as("나에게 맡긴 것은 조용하다").isEmpty();

        schedules.update(mom, created.id(), created.version(), update("병원 예약", dad.getId()));
        waitUntil(() -> fcm.calls.size() == 1);
        assertThat(fcm.calls.get(0)).containsExactly(token("dad"));

        // 엄마가 제목만 고친다 — 담당은 그대로 아빠. 앱은 PATCH 에 담당을 늘 같이 보낸다.
        // (아빠 자신이 고치면 "나 자신" 규칙에 걸려 이 규칙이 안 재진다 — 남이 고쳐야 "안 바뀜" 이 잰다.)
        schedules.update(mom, created.id(), created.version() + 1, update("병원 예약(오후)", dad.getId()));
        settle();
        assertThat(fcm.calls).as("담당이 안 바뀌면 배정이 아니다").hasSize(1);
    }

    @Test
    @DisplayName("담당자가 전체 끄기를 했거나 토큰이 없으면 FCM 을 부르지 않는다")
    void disabledOrTokenlessAssigneeIsSkipped() throws Exception {
        preferences.setEnabled(dad.getId(), false);
        schedules.create(mom, request("병원 예약", dad.getId()));
        settle();
        assertThat(fcm.calls).isEmpty();

        preferences.setEnabled(dad.getId(), true);
        deviceTokens.revokeAllOf(dad.getId());
        schedules.create(mom, request("병원 예약 2", dad.getId()));
        settle();
        assertThat(fcm.calls).isEmpty();
    }

    // ─────────────────────────── 도구 ───────────────────────────

    private ScheduleRequest request(String title, Long assignee) {
        return new ScheduleRequest(ScheduleOwnerKind.GROUP, groupId, null, ScheduleKind.VET, title, null,
                FAR, LocalTime.of(10, 30), assignee, null, null);
    }

    private ScheduleUpdateRequest update(String title, Long assignee) {
        return new ScheduleUpdateRequest(null, ScheduleKind.VET, title, null, FAR, LocalTime.of(10, 30),
                assignee, null, null, null);
    }

    private User signUp(String nickname) {
        return users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("assign-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
    }

    private String token(String device) {
        return "assign-" + serial + "-" + device;
    }

    /** 비동기 발송이 있었다면 도착했을 만큼 기다린다 — "안 온다" 를 재는 자리다. */
    private static void settle() throws InterruptedException {
        Thread.sleep(400);
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
                throw new AssertionError("기다리다 끊겼다", e);
            }
        }
    }
}
