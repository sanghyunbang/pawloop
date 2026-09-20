package com.heattrip.heat_trip_backend.observability.alert;

import com.heattrip.heat_trip_backend.moderation.ReportReason;
import com.heattrip.heat_trip_backend.moderation.ReportReceipt;
import com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;
import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * <b>운영 기본 설정에서</b> 신고 접수가 안 터진다 — 이슈 #707 §7 ⑥.
 *
 * <p>가짜를 하나도 안 끼운다. 다른 검사가 전부 가짜 슬랙만 쓰면, 운영이 실제로 도는 설정
 * ({@code observability.slack.enabled=false} · 신고 웹훅 비어 있음)은 <b>한 번도 안 도는 셈</b>이다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} 한 줄뿐인 것은 컨텍스트 캐시를 가짜 없는 쪽과 나누기
 * 위해서다(#21 §5).
 */
@SpringBootTest
class ReportAlertDefaultConfigIntegrationTest extends AbstractMySqlIntegrationTest {

    @Autowired private Reports reports;
    @Autowired private ReportAlertListener listener;
    @Autowired private ObservabilityProperties props;

    @Test
    @DisplayName("신고 웹훅이 비어 있으면 접수는 그대로 되고, 안 나간 것이 '실패' 로 한 번 세어진다")
    void filingWorksWithAlertsOff() throws Exception {
        assertThat(props.getSlack().getReportWebhookUrl())
                .as("이 검사는 운영 기본값(비어 있음)을 전제한다 — 채워져 있으면 다른 검사가 필요하다")
                .isNullOrEmpty();
        double before = listener.failureCount();

        ReportReceipt receipt = reports.file(1L, 2L, ReportReason.OTHER, null,
                List.of(ReportSnapshotInput.target(ReportTarget.post(5L), 2L, "누구", "제목", "본문",
                        Instant.parse("2026-09-18T05:03:00Z"))));

        assertThat(receipt.reportId()).isPositive();
        for (int i = 0; i < 100 && listener.failureCount() == before; i++) {
            Thread.sleep(50);
        }
        assertThat(listener.failureCount())
                .as("웹훅이 비어 안 나간 것도 '실패' 로 센다 — 켜 둔 줄 알았는데 안 나가는 것을 지표로 본다")
                .isEqualTo(before + 1);
    }
}
