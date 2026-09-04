package com.heattrip.heat_trip_backend.chat;

import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;
import com.heattrip.heat_trip_backend.chat.entity.ChatReport;
import com.heattrip.heat_trip_backend.chat.entity.ChatReportedMessage;
import com.heattrip.heat_trip_backend.chat.repository.ChatMessageRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatReportRepository;

import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.Clock;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Optional;
import java.util.Set;

/**
 * 메시지 신고 — 이슈 #82. 근거는 Apple App Store Review Guideline 1.2 와 Google Play UGC 정책이다.
 *
 * <h2>왜 {@link ChatRoomService} 에 넣지 않았나</h2>
 * <p>그 클래스가 이미 방·초대·멤버십·메시지 넷을 들고 있고, 신고는 그 넷 어디에도 안 걸리는
 * 다섯 번째다. 겹치는 것은 <b>멤버십 판정 하나</b>뿐이라 그것만 빌려 쓴다.
 *
 * <h2>이 서비스가 하지 않는 것</h2>
 * <ul>
 *   <li><b>자동 차단하지 않는다.</b> 카카오는 신고하면 자동 차단이고 "신고 후에는 취소할 수
 *       없습니다" 라는 경고까지 단다(https://cs.kakao.com/helps_html/1073199401). 가족방에서
 *       그건 되돌릴 수 없는 사고가 된다. 가리기는 <b>따로 부르는 것</b>이고 앱의 체크박스
 *       기본값은 꺼져 있다.</li>
 *   <li><b>피신고자에게 아무것도 보내지 않는다.</b> 알림 경로가 없는 것이 아니라
 *       <b>만들지 않는 것</b>이다 — 왓츠앱·카카오·라인·디스코드 넷이 전부 무통지를 문서에
 *       명시한다.</li>
 *   <li><b>누적 신고로 자동 조치하지 않는다.</b> 오탐이 곧바로 가족방 사고가 된다
 *       (#82 "넣지 않는 것").</li>
 * </ul>
 */
@Service
@Transactional(readOnly = true)
public class ChatReportService {

    /**
     * 한 신고에 담을 수 있는 메시지 수.
     *
     * <p>카카오 일반채팅방과 같은 숫자다(https://cs.kakao.com/helps_html/1073199392).
     * 방 단위 신고는 넣지 않는다 — 가족방에서 방 전체를 신고하는 동작은 뜻이 불분명하다.
     *
     * <p><b>{@code ChatLimits} 가 아니라 여기 있는 이유</b>: 그쪽은 요금제에 따라 달라지는
     * 수를 답하는 자리다. 신고 개수는 등급과 무관하고 앞으로도 그럴 것이다 — 돈을 더 낸다고
     * 신고를 더 붙일 수 있어야 할 이유가 없다.
     */
    public static final int MAX_MESSAGES_PER_REPORT = 3;

    /**
     * 고른 메시지 앞뒤로 함께 기록할 개수.
     *
     * <p>맥락 없이 한 줄만 보면 판단이 안 된다. 왓츠앱도 신고에 앞뒤 메시지를 함께 받는다
     * (https://faq.whatsapp.com/1142481766359885).
     */
    public static final int CONTEXT_RADIUS = 5;

    /** 메모 칸의 폭. {@code chat_report.memo} 와 같은 수다. */
    private static final int MAX_MEMO_LENGTH = 500;

    private final ChatReportRepository reports;
    private final ChatMessageRepository messages;
    private final ChatRoomService roomService;
    private final Clock clock;

    public ChatReportService(ChatReportRepository reports,
                             ChatMessageRepository messages,
                             ChatRoomService roomService,
                             Clock clock) {
        this.reports = reports;
        this.messages = messages;
        this.roomService = roomService;
        this.clock = clock;
    }

    /**
     * 신고 한 건을 <b>접수 직전까지</b> 만든다 — 이슈 #254.
     *
     * <h2>저장은 여기서 안 한다</h2>
     * <p>예전에는 이 메서드가 {@code chat_report} 에 저장했다. 신고 표가 둘이라 운영자가 두
     * 군데를 봐야 했고, 그것을 합치면서 <b>판정은 여기 남고 저장만 나갔다.</b>
     *
     * <p>{@code chat} 은 {@code moderation} 을 못 부른다 — 둘 다
     * {@code allowedDependencies = &#123;&#125;} 이고 {@code ChatBoundaryArchitectureTest} §B 가
     * 막는다. 그래서 값으로 내보내고, {@code chatweb} 이 그것을 옮겨 접수한다.
     *
     * <p>돌려주는 것이 <b>본문 사본</b>이라 접수까지 한 트랜잭션일 필요가 없다. 그 사이에
     * 원본이 바뀌어도 저장되는 것은 읽은 순간의 사본이고, 그게 사본이 있는 이유다.
     *
     * @param roomId         신고가 일어난 방
     * @param reporterUserId 신고한 사람. <b>살아 있는 멤버여야 한다</b>
     * @param roomSeqs       고른 메시지의 {@code room_seq}.
     *                       1개 이상 {@value #MAX_MESSAGES_PER_REPORT} 개 이하
     * @param reason         분류. 계약이 정한 닫힌 목록({@link ChatReportReason})이고 필수다
     * @param memo           덧붙이는 말. 비워도 된다
     * @return 접수할 값. <b>신고자는 들어 있지 않다</b>
     * @throws org.springframework.web.server.ResponseStatusException 그 방의 멤버가 아닐 때(403)
     * @throws ChatLimitViolationException 고른 것이 규칙에 안 맞을 때
     */
    @Transactional(readOnly = true)
    public ChatReportDraft draft(long roomId, long reporterUserId,
                                 Collection<Long> roomSeqs, String reason, String memo) {
        // 없는 방과 남의 방이 같은 답(403)인 것은 ChatRoomService 와 같은 이유다 —
        // 방 존재 여부는 그 방 멤버에게만 의미가 있다.
        requireLiveMember(roomId, reporterUserId);

        // 분류를 먼저 본다 — 모르는 값을 OTHER 로 눕히면 앱의 오타가 조용히 통과해서
        // 운영자가 세는 숫자가 소리 없이 틀어진다.
        ChatReportReason classified = ChatReportReason.fromWire(reason)
                .orElseThrow(() -> new ChatLimitViolationException(ChatErrorCode.REPORT_REASON_UNKNOWN));

        Set<Long> wanted = distinct(roomSeqs);
        if (wanted.isEmpty()) {
            throw new ChatLimitViolationException(ChatErrorCode.REPORT_EMPTY);
        }
        if (wanted.size() > MAX_MESSAGES_PER_REPORT) {
            throw new ChatLimitViolationException(ChatErrorCode.REPORT_MESSAGE_LIMIT);
        }

        List<ChatMessage> found = messages.findByRoomIdAndRoomSeqIn(roomId, wanted);
        if (found.size() != wanted.size()) {
            throw new ChatLimitViolationException(ChatErrorCode.REPORT_MESSAGE_NOT_FOUND);
        }

        long reportedUserId = singleSender(found);
        if (reportedUserId == reporterUserId) {
            throw new ChatLimitViolationException(ChatErrorCode.REPORT_SELF);
        }

        // 맥락 범위(min-5 ~ max+5)를 여기서 안 만든다. 그 두 수는 대상들의 room_seq 와
        // CONTEXT_RADIUS 에서 완전히 유도되는 파생값이라, room_seq 를 사본에 남기면
        // 언제든 다시 셀 수 있다 (#254).
        List<ChatReportDraft.Target> targets = new ArrayList<>(found.size());
        for (ChatMessage message : found) {
            targets.add(new ChatReportDraft.Target(
                    message.getId(),
                    message.getRoomSeq(),
                    message.getSenderUserId(),
                    message.getSenderName(),
                    message.getBody(),
                    message.getContentType(),
                    ChatTime.toInstant(message.getCreatedAt())));
        }

        return new ChatReportDraft(roomId, reportedUserId,
                classified.wireValue(), trimmedMemo(memo), List.copyOf(targets));
    }

    /**
     * 남은 신고 하나를 읽는다.
     *
     * <p><b>HTTP 로 열지 않았다.</b> 이것을 읽어야 하는 사람은 운영자인데 관리자 인증이
     * 아직 없고, 그것 없이 경로를 열면 <b>신고 내용이 누구에게나 보인다</b>. 이슈 #82 의
     * "어디" 표에도 운영자 화면은 없다.
     *
     * <p>그러면 왜 지금 있는가 — <b>스냅샷이 원본과 무관하게 살아 있다는 것을 확인할 수
     * 있어야</b> 하기 때문이다(#82 완료 조건 1). 확인할 방법이 없는 보존은 보존이 아니다.
     */
    public Optional<ChatReportView> findReport(long reportId) {
        return reports.findById(reportId).map(ChatReportService::viewOf);
    }

    /**
     * 그 방의 살아 있는 멤버인가.
     *
     * <p><b>403 이다.</b> 처음에 404 로 냈다가 고쳤다 — {@code ChatRoomService#postMessage} 를
     * 비롯한 방 id 를 받는 경로가 전부 403 이고, 여기만 404 면 <b>방 id 를 훑어 "있는 방/없는
     * 방" 을 가려낼 수 있다.</b> 없는 방과 남의 방은 같은 답이어야 한다.
     *
     * <p>{@code ResponseStatusException} 을 쓰는 것도 그쪽과 같다. 한도 위반과 달리 여기는
     * 앱이 갈라야 할 화면이 하나뿐이라 {@code ChatErrorCode} 를 만들 이유가 없다.
     */
    private void requireLiveMember(long roomId, long userId) {
        if (!roomService.isLiveMember(roomId, userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "이 방의 멤버가 아닙니다.");
        }
    }

    /** 중복은 세지 않는다 — 같은 것을 세 번 보내는 것으로 상한을 넘길 수는 없다. */
    private static Set<Long> distinct(Collection<Long> roomSeqs) {
        Set<Long> wanted = new LinkedHashSet<>();
        if (roomSeqs != null) {
            for (Long seq : roomSeqs) {
                if (seq != null) {
                    wanted.add(seq);
                }
            }
        }
        return wanted;
    }

    private static long singleSender(List<ChatMessage> found) {
        long sender = found.get(0).getSenderUserId();
        for (ChatMessage message : found) {
            if (!message.getSenderUserId().equals(sender)) {
                throw new ChatLimitViolationException(ChatErrorCode.REPORT_MIXED_SENDERS);
            }
        }
        return sender;
    }

    private static ChatReportedMessage snapshotOf(ChatMessage message) {
        return ChatReportedMessage.builder()
                .messageId(message.getId())
                .roomSeq(message.getRoomSeq())
                .senderUserId(message.getSenderUserId())
                .senderName(message.getSenderName())
                // 본문을 여기서 자르거나 다듬지 않는다. 신고는 "실제로 무슨 말이 있었나" 다.
                .body(message.getBody())
                .contentType(message.getContentType())
                .sentAt(message.getCreatedAt())
                .build();
    }

    private static String trimmedMemo(String memo) {
        if (memo == null || memo.isBlank()) {
            return null;
        }
        String trimmed = memo.trim();
        // 컬럼 폭에서 잘라 둔다. 안 자르면 긴 메모 하나가 INSERT 를 500 으로 만든다 —
        // content_type 이 없던 시절 같은 방식으로 터진 적이 있다(ChatMessage javadoc).
        return trimmed.length() > MAX_MEMO_LENGTH
                ? trimmed.substring(0, MAX_MEMO_LENGTH)
                : trimmed;
    }

    private static ChatReportView viewOf(ChatReport report) {
        List<ChatReportedMessageView> snapshots = report.getMessages().stream()
                .map(m -> new ChatReportedMessageView(
                        m.getRoomSeq(), m.getSenderUserId(), m.getSenderName(),
                        m.getBody(), m.getContentType(), m.getSentAt()))
                .toList();

        return new ChatReportView(
                report.getId(),
                report.getReportedUserId(),
                report.getRoomId(),
                report.getContextFromSeq(),
                report.getContextToSeq(),
                report.getReason(),
                report.getMemo(),
                report.getCreatedAt(),
                snapshots);
    }
}
