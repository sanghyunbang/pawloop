package com.heattrip.heat_trip_backend.chatweb;

import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;

import com.heattrip.heat_trip_backend.chat.ChatReportDraft;
import com.heattrip.heat_trip_backend.chat.ChatReportService;
import com.heattrip.heat_trip_backend.moderation.ReportReason;
import com.heattrip.heat_trip_backend.moderation.ReportReceipt;
import com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput;
import com.heattrip.heat_trip_backend.moderation.Reports;

import org.springframework.stereotype.Component;

/**
 * 채팅 신고를 {@code moderation} 에 접수한다 — 이슈 #254.
 *
 * <h2>왜 여기인가</h2>
 * <p>신고 표가 둘이었다. 합치려면 누군가 {@code chat} 과 {@code moderation} 을 <b>둘 다</b>
 * 불러야 하는데, 그 둘은 서로를 못 부른다 — 둘 다 {@code allowedDependencies = &#123;&#125;} 다.
 *
 * <p>{@code chatweb} 은 이미 그 둘을 선언해 뒀다. {@code ChatMessages}·{@code ChatRooms} 가
 * 같은 자리에서 {@code chat} 과 {@code moderation.Blocks} 를 함께 쓴다 —
 * <b>모듈 경계를 한 칸도 안 열고</b> 이 조립을 놓을 수 있는 유일한 자리다.
 *
 * <h2>{@code @Transactional} 이 없다</h2>
 * <p>이 패키지의 package-info 가 <b>"판정도 트랜잭션도 여기 없다"</b> 고 못 박았고,
 * {@code ChatMessages} 가 그 문장을 그대로 반복한다. 그 규약을 지킨다.
 *
 * <p>지켜도 되는 이유가 있다. {@link ChatReportDraft} 는 <b>본문을 값으로 들고 있다</b> —
 * 읽은 뒤 접수하기 전에 원본이 바뀌어도 저장되는 것은 읽은 순간의 사본이고, 그게 사본이
 * 있는 이유다. 접수 자체({@link Reports#file})는 그 안에서 한 트랜잭션이다.
 *
 * <h2>방 좌표를 맥락 한 줄로 남긴다</h2>
 * <p>{@code chat_report.room_id} 가 있던 자리다. {@code ChatReport} javadoc 이 <b>"방이
 * 지워지면 chat_message 는 CASCADE 로 함께 사라지지만 신고 기록까지 사라지면 안 된다"</b>
 * 고 적어 뒀고, 통합 테스트가 그 성질을 직접 잰다.
 *
 * <p>그 줄은 <b>사본이 아니다.</b> 본문 칸이 전부 비어 있다 — 신고당하지 않은 사람의 말은
 * 한 줄도 안 베면서 방 id 만 남긴다. 저장하는 개인정보가 오늘보다 늘지 않는다.
 */
@Component
public class ChatReports {

    private final ChatReportService chat;
    private final Reports reports;

    public ChatReports(ChatReportService chat, Reports reports) {
        this.chat = chat;
        this.reports = reports;
    }

    /**
     * 고른 메시지들을 신고로 접수한다.
     *
     * @throws IllegalStateException 분류가 {@code moderation} 의 어휘에 없을 때. 프로그래밍
     *                               오류다 — {@code chat} 이 이미 검증했고 두 어휘는 같아야 한다
     */
    public ReportReceipt file(long roomId, long reporterUserId,
                              Collection<Long> roomSeqs, String reason, String memo) {
        ChatReportDraft draft = chat.draft(roomId, reporterUserId, roomSeqs, reason, memo);

        // 두 모듈이 같은 어휘를 쓰지만 타입은 각자의 것이다. 여기서 옮기다 실패하면
        // 그것은 두 어휘가 갈렸다는 뜻이고, 조용히 OTHER 로 눕히면 운영자가 세는 숫자가
        // 소리 없이 틀어진다.
        ReportReason classified = ReportReason.fromWire(draft.reason())
                .orElseThrow(() -> new IllegalStateException(
                        "채팅의 신고 사유 '" + draft.reason() + "' 가 moderation 의 어휘에 없습니다."));

        List<ReportSnapshotInput> inputs = new ArrayList<>(draft.targets().size() + 1);
        for (ChatReportDraft.Target target : draft.targets()) {
            inputs.add(ReportSnapshotInput.chatMessage(
                    target.messageId(), target.roomSeq(), target.senderUserId(),
                    target.senderName(), target.body(), target.contentType(), target.sentAt()));
        }
        inputs.add(ReportSnapshotInput.chatRoom(draft.roomId(), Instant.now()));

        return reports.file(reporterUserId, draft.reportedUserId(),
                classified, draft.memo(), inputs);
    }
}
