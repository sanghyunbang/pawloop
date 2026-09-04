package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;
import java.util.List;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 대상 줄들이 서로 앞뒤가 맞는지 — 이슈 #254.
 *
 * <h2>왜 이 검사가 새로 필요한가</h2>
 * <p>좌표가 {@code report} 부모에 있을 때는 <b>"대상이 정확히 하나"</b> 가 구조로 보장됐다 —
 * 컬럼이 하나뿐이니 둘을 넣을 방법이 없었다.
 *
 * <p>채팅 신고가 한 건에 메시지 셋까지라 좌표를 {@code report_snapshot} 으로 내렸고, 그
 * 순간 <b>그 보장이 사라졌다.</b> {@code Reports#requireCoherentTargets} 가 대신 든다.
 *
 * <h2>DB 가 못 막는 것들이다</h2>
 * <p>{@code report_snapshot} 에는 role 개수를 세는 제약이 없다 — 한 신고에 대상 줄이 넷
 * 있어도 SQL 로는 통과한다. 종류가 섞이는 것도, 같은 좌표가 두 번 오는 것도 마찬가지다.
 * 그래서 코드가 막고, 여기서 그것을 잰다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} 한 줄뿐인 것은 컨텍스트 캐시를 나누기 위해서다(#21).
 */
@SpringBootTest
class ReportTargetRulesTest extends AbstractMySqlIntegrationTest {

    @Autowired
    private Reports reports;

    private static final Instant WHEN = Instant.parse("2026-09-04T00:00:00Z");

    @Test
    @DisplayName("대상이 하나도 없으면 거절한다 — 사본 없는 신고는 원본이 지워지면 아무것도 못 말한다")
    void atLeastOneTarget() {
        assertThatThrownBy(() -> reports.file(1L, 2L, ReportReason.SPAM, null,
                List.of(context(ReportTarget.post(7), "글"))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("대상이 하나도 없습니다");
    }

    @Test
    @DisplayName("커뮤니티 대상은 하나까지다 — 글 둘을 한 건으로 묶으면 운영자가 무엇을 볼지 모른다")
    void communityAllowsOnlyOneTarget() {
        assertThatThrownBy(() -> reports.file(1L, 2L, ReportReason.SPAM, null,
                List.of(target(ReportTarget.post(7), "하나"), target(ReportTarget.post(8), "둘"))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("1개까지");
    }

    @Test
    @DisplayName("채팅 대상은 셋까지고 넷은 거절한다 — 상한이 ChatLimits 와 같아야 한다")
    void chatAllowsThreeTargets() {
        assertThatCode(() -> reports.file(1L, 2L, ReportReason.ABUSE, null,
                List.of(chat(11, 1), chat(12, 2), chat(13, 3),
                        ReportSnapshotInput.chatRoom(99, WHEN))))
                .doesNotThrowAnyException();

        assertThatThrownBy(() -> reports.file(1L, 2L, ReportReason.ABUSE, null,
                List.of(chat(21, 1), chat(22, 2), chat(23, 3), chat(24, 4))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("3개까지");
    }

    @Test
    @DisplayName("방은 대상이 될 수 없다 — 가족방에서 방 전체를 신고하는 동작은 뜻이 불분명하다")
    void aRoomCannotBeATarget() {
        assertThatThrownBy(() -> reports.file(1L, 2L, ReportReason.ABUSE, null,
                List.of(target(ReportTarget.chatRoom(9), "방"))))
                .as("ChatReportService 가 그 모양을 명시적으로 배제했다. 상한이 0 인 것이 그 뜻이다")
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("0개까지");
    }

    @Test
    @DisplayName("대상 종류가 섞이면 거절한다 — 신고당한 사람도 하나로 안 정해진다")
    void targetsMustShareOneType() {
        assertThatThrownBy(() -> reports.file(1L, 2L, ReportReason.SPAM, null,
                List.of(target(ReportTarget.post(7), "글"), chat(11, 1))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("종류가 하나여야");
    }

    @Test
    @DisplayName("같은 좌표가 두 번 오면 거절한다 — 앱이 같은 것을 반복해 상한을 우회한다")
    void duplicateTargetsAreRejected() {
        assertThatThrownBy(() -> reports.file(1L, 2L, ReportReason.ABUSE, null,
                List.of(chat(11, 1), chat(11, 1))))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("두 번 실렸습니다");
    }

    @Test
    @DisplayName("커뮤니티 댓글 신고는 대상 하나 + 맥락 하나로 통과한다 — 맥락은 상한에 안 센다")
    void aCommentReportCarriesItsParentAsContext() {
        ReportReceipt receipt = reports.file(1L, 2L, ReportReason.ABUSE, null,
                List.of(target(ReportTarget.comment(5), "댓글"),
                        context(ReportTarget.post(7), "부모 글")));

        assertThat(receipt.reportId())
                .as("맥락 줄이 상한에 세어지면 댓글 신고가 통째로 막힌다")
                .isPositive();
    }

    // ─────────────────────────── 준비물 ───────────────────────────

    private static ReportSnapshotInput target(ReportTarget at, String body) {
        return ReportSnapshotInput.target(at, 9L, "쓴사람", null, body, WHEN);
    }

    private static ReportSnapshotInput context(ReportTarget at, String body) {
        return ReportSnapshotInput.context(at, 9L, "쓴사람", null, body, WHEN);
    }

    private static ReportSnapshotInput chat(long messageId, long roomSeq) {
        return ReportSnapshotInput.chatMessage(
                messageId, roomSeq, 9L, "보낸사람", "말 " + roomSeq, "text", WHEN);
    }
}
