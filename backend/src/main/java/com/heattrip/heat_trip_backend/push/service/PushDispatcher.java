package com.heattrip.heat_trip_backend.push.service;

import com.heattrip.heat_trip_backend.chat.ChatMessagePosted;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.push.PushMessage;
import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import com.heattrip.heat_trip_backend.push.fcm.FcmClient;
import com.heattrip.heat_trip_backend.push.fcm.FcmSendResult;
import com.heattrip.heat_trip_backend.push.metrics.PushMetrics;
import com.heattrip.heat_trip_backend.schedule.ScheduleAssigned;
import com.heattrip.heat_trip_backend.user.UserSessionsRevoked;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.time.Clock;
import java.time.LocalDate;
import java.util.List;

/**
 * 커밋된 사건을 받아 기기로 보낸다 (이슈 #83).
 *
 * <h2>왜 {@code AFTER_COMMIT} + {@code @Async} 인가</h2>
 * <p>메시지 저장 트랜잭션 안에서 FCM 을 부르면 그 HTTP 왕복이 곧 채팅 응답 시간이고, 방 행 잠금을
 * 쥔 채 기다리므로 그 방의 다른 전송까지 줄을 선다. 커밋 전에 보내면 롤백된 메시지의 알림이 나간다.
 * 그래서 커밋 <b>뒤</b>에, <b>다른 스레드</b>에서 보낸다({@code AsyncConfig.pushExecutor}).
 * {@code PushDispatchIntegrationTest} 가 둘을 각각 잰다 — 발송 시점에 트랜잭션이 없고 메시지 행이
 * 다른 연결에서 보이는가, 그리고 전송 응답이 발송을 기다리지 않는가.
 *
 * <h2>실패는 삼킨다</h2>
 * <p>여기서 던지면 실행기 스레드에서 로그만 남고 아무도 못 본다. 대신 세고({@link PushMetrics})
 * 경고 로그를 남긴다. 알림은 최선 노력이다 — 메시지는 이미 저장됐고 다음 폴링이 그것을 가져온다.
 *
 * <h2>수신자 셋을 거른다</h2>
 * <ol>
 *   <li>방의 살아 있는 멤버 중 보낸 사람과 음소거한 사람을 뺀다 — {@code chat} 이 답한다.</li>
 *   <li>전체 끄기를 한 사람을 뺀다 — 이 모듈이 답한다.</li>
 *   <li>살아 있는 토큰이 있는 사람만 남는다.</li>
 * </ol>
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class PushDispatcher {

    private final ChatRoomService chatRooms;
    private final PushPreferenceService preferences;
    private final DeviceTokenService deviceTokens;
    private final FcmClient fcm;
    private final PushMetrics metrics;

    /** "내일" 을 가르는 시계 — {@code ClockConfig} 의 {@code Asia/Seoul} 빈이다. */
    private final Clock clock;

    @Async("pushExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onMessagePosted(ChatMessagePosted event) {
        try {
            List<Long> members = chatRooms.notifiableMembers(event.roomId(), event.senderUserId());
            List<Long> recipients = preferences.onlyEnabled(members);
            List<DeviceToken> tokens = deviceTokens.activeTokensOf(recipients);
            if (tokens.isEmpty()) {
                metrics.skipped();
                return;
            }
            FcmSendResult result = fcm.send(tokens.stream().map(DeviceToken::getToken).toList(),
                    PushMessage.forChat(event));
            if (!result.unregistered().isEmpty()) {
                deviceTokens.revokeTokens(result.unregistered());
            }
            metrics.record(result);
        } catch (RuntimeException e) {
            metrics.dispatchFailed();
            log.warn("푸시 발송 실패 — 방 {} 메시지 {}: {}", event.roomId(), event.messageId(), e.toString());
        }
    }

    /**
     * 가족이 <b>나를 담당으로</b> 일정을 만들거나 고쳤다 — 이슈 #735.
     *
     * <p>받는 사람은 담당자 한 명이다. 방별 음소거 같은 것은 없고, 전체 끄기와 살아 있는 토큰만
     * 본다 — 채팅 푸시의 2·3 단계와 같다. 배정한 사람은 사건에 안 들어온다({@code schedule} 이
     * 담당이 나면 발행하지 않는다).
     */
    @Async("pushExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onScheduleAssigned(ScheduleAssigned event) {
        try {
            List<Long> recipients = preferences.onlyEnabled(List.of(event.assigneeUserId()));
            List<DeviceToken> tokens = deviceTokens.activeTokensOf(recipients);
            if (tokens.isEmpty()) {
                metrics.skipped();
                return;
            }
            FcmSendResult result = fcm.send(tokens.stream().map(DeviceToken::getToken).toList(),
                    PushMessage.forScheduleAssigned(event, LocalDate.now(clock)));
            if (!result.unregistered().isEmpty()) {
                deviceTokens.revokeTokens(result.unregistered());
            }
            metrics.record(result);
        } catch (RuntimeException e) {
            metrics.dispatchFailed();
            log.warn("배정 푸시 발송 실패 — 일정 {} 담당 {}: {}",
                    event.scheduleId(), event.assigneeUserId(), e.toString());
        }
    }

    /**
     * 로그아웃은 전 기기의 토큰을 폐기하고, 탈퇴는 행을 지운다.
     *
     * <p>{@code user} 가 이 모듈을 모르므로 직접 부르지 않고 사건으로 받는다. 커밋 뒤라야 한다 —
     * 탈퇴 트랜잭션이 롤백됐는데 토큰만 사라지면 그 사람은 알림을 영영 못 받는다.
     */
    @Async("pushExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onSessionsRevoked(UserSessionsRevoked event) {
        try {
            if (event.accountDeleted()) {
                deviceTokens.deleteAllOf(event.userId());
                preferences.deleteOf(event.userId());
            } else {
                deviceTokens.revokeAllOf(event.userId());
            }
        } catch (RuntimeException e) {
            metrics.dispatchFailed();
            log.warn("기기 토큰 정리 실패 — 사용자 {}: {}", event.userId(), e.toString());
        }
    }
}
