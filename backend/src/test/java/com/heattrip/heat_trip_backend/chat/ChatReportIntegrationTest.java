package com.heattrip.heat_trip_backend.chat;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;
import com.heattrip.heat_trip_backend.chat.repository.ChatMessageRepository;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 메시지 신고 — 이슈 #82 완료 조건 1 · 2 · 9.
 *
 * <h2>여기서 재는 것</h2>
 * <p><b>원본이 사라진 뒤에도 신고가 읽히는가.</b> 그게 스냅샷의 존재 이유이고, 참조로
 * 되돌리면 이 파일의 첫 두 테스트가 빨개진다(완료 조건 9).
 *
 * <p>원본을 지우는 방식이 두 가지다.
 * <ol>
 *   <li><b>메시지 소프트 삭제</b> — {@code deleted_at} 을 찍고 본문을 비운다. 그게 이
 *       도메인이 정한 삭제이고({@code ChatMessage} javadoc), 신고당한 사람이 실제로 할 수
 *       있는 일이다.</li>
 *   <li><b>방 통째로 삭제</b> — {@code chat_message} 는 {@code ON DELETE CASCADE} 라 방과
 *       함께 사라진다. 신고까지 함께 사라지면 <b>방을 지우는 것으로 신고를 지울 수
 *       있게</b> 된다.</li>
 * </ol>
 *
 * <p>둘 다 JPA 가 아니라 SQL 로 한다. 삭제 엔드포인트가 아직 없고(M2.7), 여기서 확인하려는
 * 것은 "우리 코드가 어떻게 지우는가" 가 아니라 <b>행이 사라져도 신고가 남는가</b> 다.
 *
 * <h2>애너테이션이 {@code @SpringBootTest} 한 줄뿐인 것은 의도다</h2>
 * <p>{@code ChatMessageIntegrationTest}·{@code SchemaDdlDriftTest} 와 글자 그대로 같아야
 * 컨텍스트 캐시를 공유한다(#21). {@code @Transactional} 을 안 붙인 것은 <b>커밋된 뒤에도
 * 남는가</b> 를 보는 테스트이기 때문이다 — 롤백하면 원본 삭제 자체가 되돌아간다.
 */
@SpringBootTest
class ChatReportIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String ORIGIN_KIND = "CHATREPORT_TEST";

    /** 방의 출처 쌍과 사용자 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired
    private ChatReportService reportService;

    @Autowired
    private ChatRoomService roomService;

    @Autowired
    private ChatMessageRepository messages;

    @Autowired
    private UserRepository users;

    @Autowired
    private JdbcTemplate jdbc;

    // ─────────────────────────── 완료 조건 1 ───────────────────────────

    @Test
    @DisplayName("신고한 메시지는 원본이 지워진 뒤에도 본문까지 그대로 읽힌다")
    void theSnapshotOutlivesTheOriginalMessage() {
        Fixture f = fixture();
        long badSeq = send(f, f.troll, "여기서 하면 안 되는 말");

        long reportId = reportService
                .report(f.roomId, f.reporter.getId(), List.of(badSeq), "abuse", "욕설입니다").id();

        // 신고당한 사람이 지운다 — 이 도메인의 삭제는 소프트이고 본문을 비운다.
        jdbc.update("update chat_message set body = '', deleted_at = now(6) "
                + "where room_id = ? and room_seq = ?", f.roomId, badSeq);

        ChatReportView report = reportService.findReport(reportId).orElseThrow();

        assertThat(report.messages()).singleElement()
                .satisfies(snapshot -> {
                    assertThat(snapshot.body())
                            .as("""
                                    원본을 참조만 하면 여기가 빈 문자열이 된다. 그 상태로는 무엇이
                                    신고됐는지 알 수 없어서 판단이 불가능하다.
                                    """)
                            .isEqualTo("여기서 하면 안 되는 말");
                    assertThat(snapshot.senderUserId()).isEqualTo(f.troll.getId());
                    assertThat(snapshot.roomSeq()).isEqualTo(badSeq);
                });

        assertThat(messages.findByRoomIdAndRoomSeqIn(f.roomId, List.of(badSeq)))
                .as("원본은 실제로 비워져 있어야 한다 — 아니면 이 테스트가 아무것도 안 잡는다")
                .singleElement()
                .extracting(ChatMessage::getBody)
                .isEqualTo("");
    }

    @Test
    @DisplayName("방이 통째로 사라져도 신고는 남는다 — 방을 지워서 신고를 지울 수 없다")
    void theSnapshotOutlivesTheWholeRoom() {
        Fixture f = fixture();
        long badSeq = send(f, f.troll, "방과 함께 사라지면 안 되는 말");

        long reportId = reportService
                .report(f.roomId, f.reporter.getId(), List.of(badSeq), "abuse", null).id();

        jdbc.update("delete from chat_room where id = ?", f.roomId);

        assertThat(reportService.findReport(reportId))
                .as("""
                        chat_message 는 ON DELETE CASCADE 라 방과 함께 사라진다.
                        chat_report 까지 방에 FK 로 묶으면 방 삭제 한 번에 신고 기록이 지워진다.
                        """)
                .get()
                .extracting(view -> view.messages().get(0).body())
                .isEqualTo("방과 함께 사라지면 안 되는 말");
    }

    @Test
    @DisplayName("앞뒤 5개 범위가 함께 남는다")
    void theContextRangeIsRecorded() {
        Fixture f = fixture();
        for (int i = 0; i < 12; i++) {
            send(f, f.troll, "메시지 " + i);
        }
        long picked = send(f, f.troll, "고른 것");

        ChatReportView report = reportService
                .report(f.roomId, f.reporter.getId(), List.of(picked), "spam", null);

        assertThat(report.contextFromSeq())
                .as("한 줄만 보면 판단이 안 된다. 어디를 봐야 하는지가 함께 남아야 한다")
                .isEqualTo(picked - ChatReportService.CONTEXT_RADIUS);
        assertThat(report.contextToSeq()).isEqualTo(picked + ChatReportService.CONTEXT_RADIUS);
    }

    @Test
    @DisplayName("방 첫 메시지를 신고해도 범위가 0 이나 음수로 내려가지 않는다")
    void theContextRangeNeverGoesBelowOne() {
        Fixture f = fixture();
        long first = send(f, f.troll, "방의 첫 줄");

        ChatReportView report = reportService
                .report(f.roomId, f.reporter.getId(), List.of(first), "spam", null);

        assertThat(report.contextFromSeq())
                .as("room_seq 는 1부터다. 0 이나 음수를 남기면 그 범위를 읽는 쪽이 헛돈다")
                .isEqualTo(1L);
    }

    // ─────────────────────────── 완료 조건 2 ───────────────────────────

    @Test
    @DisplayName("밖으로 나가는 모양에 신고자가 없다 — 문서가 아니라 타입이 막는다")
    void theViewCannotCarryTheReporter() {
        assertThat(ChatReportView.class.getRecordComponents())
                .as("""
                        record 에 필드가 없으면 어떤 응답도 그것을 실을 수 없다.
                        "싣지 마세요" 라고 문서에 적는 것과 실을 수 없게 만드는 것은 다르다.
                        """)
                .extracting(java.lang.reflect.RecordComponent::getName)
                .doesNotContain("reporterUserId", "reporterId", "reporter");
    }

    @Test
    @DisplayName("신고해도 피신고자 쪽에는 아무 변화가 없다")
    void reportingChangesNothingForTheReportedPerson() {
        Fixture f = fixture();
        long badSeq = send(f, f.troll, "신고당할 말");
        int before = roomService.myRooms(f.troll.getId()).size();
        long unreadBefore = unreadOf(f.roomId, f.troll.getId());

        reportService.report(f.roomId, f.reporter.getId(), List.of(badSeq), "abuse", "사유");

        assertThat(roomService.myRooms(f.troll.getId()))
                .as("방이 늘거나 줄면 그 자체가 통지다")
                .hasSize(before);
        assertThat(unreadOf(f.roomId, f.troll.getId()))
                .as("미읽음이 흔들리면 앱 뱃지가 움직여서 신고당한 것이 드러난다")
                .isEqualTo(unreadBefore);
    }

    // ─────────────────────────── 고른 것이 규칙에 안 맞을 때 ───────────────────────────

    @Test
    @DisplayName("3개를 넘기면 거절한다")
    void atMostThreeMessages() {
        Fixture f = fixture();
        List<Long> four = List.of(
                send(f, f.troll, "1"), send(f, f.troll, "2"),
                send(f, f.troll, "3"), send(f, f.troll, "4"));

        assertThatThrownBy(() -> reportService.report(f.roomId, f.reporter.getId(), four, "spam", null))
                .isInstanceOf(ChatLimitViolationException.class)
                .extracting(e -> ((ChatLimitViolationException) e).errorCode())
                .isEqualTo(ChatErrorCode.REPORT_MESSAGE_LIMIT);
    }

    @Test
    @DisplayName("같은 메시지를 세 번 보내도 3개 상한을 못 넘는다 — 중복은 하나로 센다")
    void duplicatesDoNotInflateTheCount() {
        Fixture f = fixture();
        long seq = send(f, f.troll, "한 줄");

        ChatReportView report = reportService.report(
                f.roomId, f.reporter.getId(), List.of(seq, seq, seq), "spam", null);

        assertThat(report.messages())
                .as("중복을 그대로 세면 앱이 같은 항목을 반복해 보내는 것만으로 상한을 우회한다")
                .hasSize(1);
    }

    @Test
    @DisplayName("아무것도 안 고르면 거절한다")
    void atLeastOneMessage() {
        Fixture f = fixture();

        assertThatThrownBy(() -> reportService.report(f.roomId, f.reporter.getId(), List.of(), "spam", null))
                .isInstanceOf(ChatLimitViolationException.class)
                .extracting(e -> ((ChatLimitViolationException) e).errorCode())
                .isEqualTo(ChatErrorCode.REPORT_EMPTY);
    }

    @Test
    @DisplayName("발신자가 섞이면 거절한다 — 신고 대상이 하나여야 한다")
    void onlyOnePersonPerReport() {
        Fixture f = fixture();
        List<Long> mixed = List.of(send(f, f.troll, "저쪽"), send(f, f.reporter, "이쪽"));

        assertThatThrownBy(() -> reportService.report(f.roomId, f.reporter.getId(), mixed, "abuse", null))
                .isInstanceOf(ChatLimitViolationException.class)
                .extracting(e -> ((ChatLimitViolationException) e).errorCode())
                .isEqualTo(ChatErrorCode.REPORT_MIXED_SENDERS);
    }

    @Test
    @DisplayName("자기 메시지는 신고할 수 없다")
    void cannotReportYourself() {
        Fixture f = fixture();
        long mine = send(f, f.reporter, "내가 쓴 것");

        assertThatThrownBy(() -> reportService.report(f.roomId, f.reporter.getId(), List.of(mine), "spam", null))
                .isInstanceOf(ChatLimitViolationException.class)
                .extracting(e -> ((ChatLimitViolationException) e).errorCode())
                .isEqualTo(ChatErrorCode.REPORT_SELF);
    }

    @Test
    @DisplayName("그 방에 없는 번호는 거절한다")
    void unknownSeqIsRejected() {
        Fixture f = fixture();
        send(f, f.troll, "하나뿐");

        assertThatThrownBy(() ->
                reportService.report(f.roomId, f.reporter.getId(), List.of(9_999L), "spam", null))
                .isInstanceOf(ChatLimitViolationException.class)
                .extracting(e -> ((ChatLimitViolationException) e).errorCode())
                .isEqualTo(ChatErrorCode.REPORT_MESSAGE_NOT_FOUND);
    }

    @Test
    @DisplayName("멤버가 아니면 방이 있는지도 알 수 없다")
    void aNonMemberCannotReport() {
        Fixture f = fixture();
        long badSeq = send(f, f.troll, "말");
        User outsider = signUp("바깥사람");

        assertThatThrownBy(() ->
                reportService.report(f.roomId, outsider.getId(), List.of(badSeq), "spam", null))
                .as("없는 방과 남의 방이 같은 답(403)이어야 방 id 를 훑어 존재를 가려낼 수 없다")
                .isInstanceOf(ResponseStatusException.class)
                .extracting(e -> ((ResponseStatusException) e).getStatusCode())
                .isEqualTo(org.springframework.http.HttpStatus.FORBIDDEN);
    }

    @Test
    @DisplayName("메모가 500자를 넘으면 잘라서 저장한다 — INSERT 가 500 으로 터지지 않는다")
    void anOverlongMemoIsTruncated() {
        Fixture f = fixture();
        long badSeq = send(f, f.troll, "말");

        ChatReportView report = reportService.report(
                f.roomId, f.reporter.getId(), List.of(badSeq), "other", "가".repeat(900));

        assertThat(report.memo()).hasSize(500);
    }

    @Test
    @DisplayName("계약에 없는 사유는 거절한다 — OTHER 로 눕히지 않는다")
    void anUnknownReasonIsRejected() {
        Fixture f = fixture();
        long badSeq = send(f, f.troll, "말");

        assertThatThrownBy(() -> reportService.report(
                f.roomId, f.reporter.getId(), List.of(badSeq), "harrassment", null))
                .as("""
                        앱의 오타를 OTHER 로 받아 주면 운영자가 세는 숫자가 소리 없이 틀어진다.
                        "이 방에 성적 내용 신고가 몇 건인가" 를 물을 수 없게 된다.
                        """)
                .isInstanceOf(ChatLimitViolationException.class)
                .extracting(e -> ((ChatLimitViolationException) e).errorCode())
                .isEqualTo(ChatErrorCode.REPORT_REASON_UNKNOWN);
    }

    @Test
    @DisplayName("사유 분류가 저장돼서 세어 볼 수 있다")
    void theClassificationIsStored() {
        Fixture f = fixture();
        long badSeq = send(f, f.troll, "말");

        ChatReportView report = reportService.report(
                f.roomId, f.reporter.getId(), List.of(badSeq), "SEXUAL", null);

        assertThat(report.reason())
                .as("대소문자를 가리지 않고 받되 저장은 계약의 wire 값 하나로 고정한다")
                .isEqualTo("sexual");
    }

    // ─────────────────────────── 준비물 ───────────────────────────

    private record Fixture(long roomId, User reporter, User troll) {}

    private Fixture fixture() {
        User reporter = signUp("신고하는사람");
        User troll = signUp("신고당하는사람");

        long serial = SEQUENCE.incrementAndGet();
        ChatRoomView room = roomService.openRoom(
                ORIGIN_KIND, "report-" + System.nanoTime() + "-" + serial,
                "신고 테스트방", "FAMILY", reporter.getId());

        // 신고당할 사람도 그 방 멤버여야 말을 남길 수 있다.
        roomService.joinByInviteCode(
                roomService.issueInvite(room.id(), reporter.getId()).code(), troll.getId());

        return new Fixture(room.id(), reporter, troll);
    }

    private User signUp(String nickname) {
        return users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("report-%d@example.com".formatted(System.nanoTime()))
                .name(nickname)
                .nickname(nickname)
                .build());
    }

    private long send(Fixture f, User sender, String body) {
        return roomService.postMessage(
                f.roomId, sender.getId(), sender.getNickname(), body, "text", null).roomSeq();
    }

    private long unreadOf(long roomId, long userId) {
        return roomService.myRooms(userId).stream()
                .filter(r -> r.room().id() == roomId)
                .findFirst()
                .map(ChatRoomSummaryView::unread)
                .orElseThrow();
    }
}
