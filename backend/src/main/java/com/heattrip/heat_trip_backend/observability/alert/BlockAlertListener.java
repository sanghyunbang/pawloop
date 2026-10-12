package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.moderation.UserBlocked;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.time.format.DateTimeFormatter;

/**
 * 누가 누구를 차단하면 운영자에게 알린다 — 애플 App Review Guideline 1.2.
 *
 * <p>1.2 는 차단 수단에 "개발자에게도 알려야 한다" 를 붙인다. 차단은 커뮤니티에서 하든 채팅에서 하든
 * {@code POST /api/blocks} 하나로 모이고, 거기서 {@code moderation.Blocks} 가 {@link UserBlocked} 를
 * 낸다. 여기는 그것을 받아 슬랙으로 보낸다.
 *
 * <h2>{@link ReportAlertListener} 와 같은 모양이다</h2>
 * <ul>
 *   <li><b>왜 여기(observability)에 있나</b> — {@code moderation} 은 나가는 참조가 0인 잎 모듈이라
 *       슬랙을 못 부르고, {@link SlackNotifier} 는 하위 패키지({@code alert})라 같은 모듈 안에서만
 *       부를 수 있다. 기준선({@code BASELINE_VIOLATIONS})이 그대로다.</li>
 *   <li><b>커밋 뒤에, 다른 스레드에서</b> — {@code AFTER_COMMIT} 이라 롤백된 차단은 안 알리고,
 *       {@code @Async} 라 {@code POST /api/blocks} 가 슬랙을 기다리지 않는다.</li>
 *   <li><b>실패는 던지지 않고 센다</b>({@code block_alert_failures_total}). {@code @Async} 뒤에서
 *       던진 예외는 아무도 못 본다. 웹훅이 비어 안 나간 것도 실패로 센다 — 켠 줄 알았는데 안 나가는
 *       것을 지표로 본다.</li>
 *   <li><b>성공도 한 줄 남긴다</b> — {@code docker logs | grep "차단 알림"} 한 번으로 갔는지가 갈린다.</li>
 * </ul>
 *
 * <h2>다른 점 하나 — 실행기를 따로 쓴다</h2>
 * <p>신고 실행기({@code reportAlertExecutor})의 "안 버린다" 는 <b>신고 입구의 한도를 전제로 한
 * 정책</b>이다({@code AsyncConfig} javadoc). 차단 알림은 그 전제가 다르므로 섞지 않는다 — 어떤 경우에도
 * 차단 알림 때문에 24시간 처리 약속이 걸린 신고 알림이 밀리면 안 된다.
 *
 * <p>그래서 차단은 자기 실행기({@code AsyncConfig.BLOCK_ALERT_EXECUTOR})를 쓰고, 넘치면 버리고 경고만
 * 한다. 버려도 차단 자체는 {@code user_block} 에 남아 있어 운영자가 DB 로 볼 수 있다.
 *
 * <h2>같은 채널로 간다</h2>
 * <p>신고 웹훅으로 보낸다({@link SlackNotifier#sendBlock}). 운영자가 손으로 들여다볼 사건이 한
 * 채널에 모여야 "이 사람이 신고도 받고 차단도 당했다" 가 한 화면에 보인다.
 */
@Component
public class BlockAlertListener {

    private static final Logger log = LoggerFactory.getLogger(BlockAlertListener.class);

    private static final DateTimeFormatter WHEN = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    private final SlackNotifier slack;
    private final Counter failures;

    public BlockAlertListener(SlackNotifier slack, MeterRegistry meters) {
        this.slack = slack;
        this.failures = Counter.builder("block_alert_failures_total")
                .description("차단 알림을 보내려다 실패한 횟수 — 차단 자체는 이미 저장돼 있다")
                .register(meters);
    }

    @Async("blockAlertExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onUserBlocked(UserBlocked event) {
        try {
            boolean sent = slack.sendBlock(format(event));
            if (sent) {
                log.info("차단 알림 보냄 — block {}", event.blockId());
            } else {
                failures.increment();
                log.warn("차단 알림이 안 나갔다 — block {} (웹훅이 비었거나 발송 실패)", event.blockId());
            }
        } catch (RuntimeException e) {
            failures.increment();
            log.warn("차단 알림 실패 — block {}: {}", event.blockId(), e.toString());
        }
    }

    /**
     * 알림 본문. 운영자가 <b>이것만 보고 DB 를 열 수 있어야</b> 한다 — {@code user_block.id} 와 양쪽
     * 사용자 id 가 그 좌표다.
     *
     * <p>이름은 없다 — {@link UserBlocked} 에 자리가 없다. 본문도 없다 — 차단은 글이 아니라 사람에 대한
     * 것이고, 무엇 때문인지는 그 사람이 받은 신고({@code report.reported_user_id})가 말한다.
     */
    static String format(UserBlocked event) {
        return ":no_entry_sign: 차단 #" + event.blockId()
                + " · u#" + event.blockerUserId() + " → u#" + event.blockedUserId() + '\n'
                + "차단당한 사람 u#" + event.blockedUserId() + '\n'
                + "차단한 사람   u#" + event.blockerUserId() + '\n'
                + "시각          "
                + WHEN.format(event.blockedAt().atZone(ReportAlertListener.DISPLAY_ZONE)) + " KST";
    }

    /** 검사가 "실패가 세어지는가" 를 재려고 읽는다. */
    double failureCount() {
        return failures.count();
    }
}
