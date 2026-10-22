package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.moderation.ReportFiled;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

/**
 * 신고가 접수되면 운영자에게 알린다 — 이슈 #707 1단계.
 *
 * <h2>왜 여기(observability)에 있나</h2>
 * <p>{@code moderation} 은 나가는 참조가 0인 잎 모듈이라 슬랙을 직접 못 부른다. 그래서 그쪽이
 * {@link ReportFiled} 를 발행하고 이쪽이 듣는다. 리스너를 <b>이 모듈 안</b>에 두는 것이 요점이다 —
 * {@link SlackNotifier} 는 하위 패키지({@code alert})라 바깥 모듈이 부르면 위반인데, 같은 모듈
 * 안에서는 검사 대상이 아니다. 기준선({@code BASELINE_VIOLATIONS}) 이 그대로다.
 *
 * <h2>커밋 뒤에, 다른 스레드에서</h2>
 * <p>{@code AFTER_COMMIT} 은 비동기가 아니다 — 커밋한 그 스레드에서 이어서 돌고, 그게 끝나야
 * {@code POST .../reports} 가 응답한다. 알림에는 그럴 이유가 없어서 {@code @Async} 를 함께 붙인다.
 * {@code push.service.PushDispatcher} 와 같은 조합이다.
 *
 * <p>실행기는 {@code pushExecutor} 를 안 쓴다. 그쪽은 큐가 차면 <b>버리고 경고만</b> 하는 정책인데
 * 채팅 푸시에는 맞지만 신고 알림이 조용히 버려지면 켠 의미가 없다. 전용 실행기
 * ({@code AsyncConfig.REPORT_ALERT_EXECUTOR}) 를 쓴다.
 *
 * <h2>실패는 던지지 않고 센다</h2>
 * <p>{@code @Async} 가 붙어 있는 한 여기서 던진 예외는 호출자에게 갈 길이 없다 — 실행기 스레드에서
 * 로그만 남고 아무도 못 본다. 그래서 "예외가 안 난다" 는 아무것도 잠그지 못하는 공짜 초록이다.
 * 대신 <b>실패를 센다</b>({@code report_alert_failures_total}). 검사는 그 수를 잰다.
 *
 * <h2>성공도 한 줄 남긴다</h2>
 * <p>처음에는 실패만 경고로 찍고 성공은 조용했다. 2026-09-20 운영에서 첫 신고가 들어왔을 때
 * "슬랙에 아무것도 없다" 고 했고 로그에는 전송 흔적이 한 줄도 없었다 — 그 침묵이 "안 갔다"
 * 인지 "갔는데 못 봤다" 인지 로그로는 판단이 안 됐고, 결국 {@code /actuator/prometheus} 의
 * {@code executor_completed_tasks_total} 과 실패 카운터 0 을 대조해서야 "갔다" 를 알았다(실제로는
 * DM 화면을 보고 있어서 못 본 것이었다). 신고는 드문 사건이라 성공 한 줄이 소음이 아니고,
 * {@code docker logs | grep "신고 알림"} 한 번으로 갔는지 안 갔는지가 갈려야 한다.
 *
 * <h2>도배를 막지 않는다</h2>
 * <p>{@link AlertRateLimiter} 를 재사용하지 않는다. 에러는 같은 스택트레이스 100번이 사건 하나지만
 * <b>신고는 같은 글 10건이 사건 10건이고 그 몰림 자체가 가장 강한 신호</b>다. 입구가 이미 막혀
 * 있다(커뮤니티 IP당 분당 10 · 채팅 사용자당 분당 10). 정말 몰리면 접되 버리지 않는 쪽으로 간다.
 */
@Component
public class ReportAlertListener {

    private static final Logger log = LoggerFactory.getLogger(ReportAlertListener.class);

    /** 표시는 KST 다 — 운영자가 한국에 있다. 저장은 UTC 인 채로 둔다. */
    static final ZoneId DISPLAY_ZONE = ZoneId.of("Asia/Seoul");
    private static final DateTimeFormatter WHEN = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm");

    private final SlackNotifier slack;
    private final Counter failures;

    public ReportAlertListener(SlackNotifier slack, MeterRegistry meters) {
        this.slack = slack;
        this.failures = Counter.builder("report_alert_failures_total")
                .description("신고 알림을 보내려다 실패한 횟수 — 신고 자체는 이미 저장돼 있다")
                .register(meters);
    }

    @Async("reportAlertExecutor")
    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onReportFiled(ReportFiled event) {
        try {
            boolean sent = slack.sendReport(format(event));
            if (sent) {
                log.info("신고 알림 보냄 — report {}", event.reportId());
            } else {
                failures.increment();
                log.warn("신고 알림이 안 나갔다 — report {} (웹훅이 비었거나 발송 실패)", event.reportId());
            }
        } catch (RuntimeException e) {
            failures.increment();
            log.warn("신고 알림 실패 — report {}: {}", event.reportId(), e.toString());
        }
    }

    /**
     * 알림 본문. 운영자가 <b>이것만 보고 DB 질의를 짤 수 있어야</b> 한다 — 읽는 화면이 없다.
     *
     * <p>무엇을 안 싣는지는 {@link ReportFiled} 가 정했고 여기는 그것을 따른다. 채팅이면 본문 자리에
     * {@code (채팅 · 본문은 DB)} 만 찍고 이름도 안 적는다.
     */
    static String format(ReportFiled event) {
        StringBuilder text = new StringBuilder(256);
        text.append(":triangular_flag_on_post: 신고 #").append(event.reportId())
                .append(" · ").append(event.reason()).append('\n');

        for (ReportFiled.Target target : event.targets()) {
            text.append("대상   ").append(target.targetType()).append(' ').append(target.targetId());
            if (target.isChat()) {
                text.append(" (채팅 · 본문은 DB)");
                if (target.authorUserId() != null) {
                    text.append(" 작성자 u#").append(target.authorUserId());
                }
            } else {
                text.append(" (글쓴이 ");
                text.append(target.authorUserId() == null ? "탈퇴" : "u#" + target.authorUserId());
                if (target.authorName() != null) {
                    text.append(" \"").append(target.authorName()).append('"');
                }
                text.append(')');
            }
            text.append('\n');
            if (!target.isChat() && target.bodyPreview() != null) {
                text.append("본문   \"").append(target.bodyPreview()).append("\"\n");
            }
        }

        text.append("신고자 u#").append(event.reporterUserId()).append('\n');
        text.append("시각   ").append(WHEN.format(event.filedAt().atZone(DISPLAY_ZONE))).append(" KST\n");
        text.append("메모   ");
        if (event.hasMemo()) {
            text.append('"').append(event.memoPreview()).append('"');
        } else {
            text.append("없음");
        }
        return text.toString();
    }

    /** 검사가 "실패가 세어지는가" 를 재려고 읽는다. */
    double failureCount() {
        return failures.count();
    }
}
