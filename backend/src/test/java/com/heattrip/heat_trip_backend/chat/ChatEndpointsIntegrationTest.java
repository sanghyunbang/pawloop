package com.heattrip.heat_trip_backend.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.chat.entity.ChatMessage;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;
import com.heattrip.heat_trip_backend.chat.repository.ChatMessageRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomMemberRepository;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 채팅 엔드포인트 네 개를 <b>HTTP 로</b> 확인한다 — 이슈 #79 완료 조건 1~9.
 *
 * <h2>왜 통합 테스트인가</h2>
 * <p>이 이슈가 보증해야 하는 것이 전부 여러 계층에 걸쳐 있다. "재전송은 200" 은 서비스의
 * 예외 번역 + 트랜잭션 경계 + 컨트롤러의 상태 코드가 함께 맞아야 성립하고, "남의 방은 403"
 * 은 서비스 판정 + 전역 예외 처리기의 봉투가 함께 맞아야 성립한다. 목으로 나누면 조각마다
 * 초록불인데 합친 동작이 틀릴 수 있다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} <b>두 줄뿐인 것은
 * 의도다</b> — {@code FamilyGroupInviteIntegrationTest}·{@code CareSharingIntegrationTest} 와
 * 글자 그대로 같아야 스프링 컨텍스트 캐시를 공유한다(#21). {@code @MockBean}·
 * {@code @TestPropertySource} 를 하나라도 붙이면 캐시 키가 갈라져 컨텍스트가 한 번 더 뜬다.
 *
 * <p>{@code @Transactional} 도 없다 — 재전송 경합 테스트가 스레드마다 <b>각자의 트랜잭션</b>을
 * 여는 것을 전제로 하고, 테스트가 트랜잭션을 감싸면 그 전제가 사라진다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ChatEndpointsIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Autowired
    private ChatRoomService chatRooms;

    @Autowired
    private ChatRoomMemberRepository chatRoomMemberRepository;

    @Autowired
    private ChatMessageRepository chatMessageRepository;

    // ─────────────────── 완료 조건 1 — 미읽음이 실제 미읽음과 같다 ───────────────────

    @Test
    @DisplayName("두 계정이 주고받으면 방 목록의 미읽음이 실제 미읽음과 같다 — COUNT 가 아니라 뺄셈이다")
    void twoAccountsTalking_seeAnUnreadCountThatMatchesReality() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);

        send(owner, room.id(), "보리 밥 줬어요", "m1").andExpect(status().isCreated());
        send(owner, room.id(), "산책도 다녀왔고요", "m2").andExpect(status().isCreated());
        send(mate, room.id(), "고마워요", "m3").andExpect(status().isCreated());

        JsonNode forMate = roomInList(mate, room.id());
        assertThat(forMate.path("lastSeq").asLong()).isEqualTo(3);
        assertThat(forMate.path("lastReadSeq").asLong()).isZero();
        assertThat(forMate.path("unread").asLong())
                .as("아직 아무것도 안 읽었으니 방의 마지막 번호 그대로다")
                .isEqualTo(3);

        markRead(mate, room.id(), 3).andExpect(status().isOk());

        assertThat(roomInList(mate, room.id()).path("unread").asLong())
                .as("읽음 커서가 마지막까지 갔으면 미읽음은 0 이다")
                .isZero();
        assertThat(roomInList(owner, room.id()).path("unread").asLong())
                .as("owner 는 mate 의 메시지를 아직 안 읽었다 — 미읽음은 사람마다 다르다")
                .isEqualTo(3);
    }

    @Test
    @DisplayName("방 목록에 마지막 메시지 미리보기와 멤버 수·역할이 실린다")
    void theRoomListCarriesThePreviewAndMyRole() throws Exception {
        Account owner = account("방장");
        Account mate = account("멤버");
        Room room = roomWith(owner, mate);

        send(mate, room.id(), "마지막으로 한 말", "preview-1").andExpect(status().isCreated());

        JsonNode forOwner = roomInList(owner, room.id());
        assertThat(forOwner.path("title").asText()).isEqualTo(room.title());
        assertThat(forOwner.path("tag").asText()).isEqualTo("테스트");
        assertThat(forOwner.path("memberCount").asInt()).isEqualTo(2);
        assertThat(forOwner.path("myRole").asText()).isEqualTo("OWNER");
        assertThat(forOwner.path("lastMessage").path("body").asText())
                .isEqualTo("마지막으로 한 말");
        assertThat(forOwner.path("lastMessage").path("senderName").asText())
                .as("이름은 스냅샷이 아니라 지금 users 의 값이다 (#78 완료 조건 4)")
                .isEqualTo("멤버");
        assertThat(roomInList(mate, room.id()).path("myRole").asText()).isEqualTo("MEMBER");
    }

    // ─────────────────── 완료 조건 2 — 30초 끊겼다 붙어도 안 놓친다 ───────────────────

    @Test
    @DisplayName("폴링이 끊긴 사이 쌓인 메시지를 afterSeq 델타가 하나도 빠뜨리지 않는다")
    void aPollingGapLosesNothing() throws Exception {
        Account owner = account("계속 보는 사람");
        Account mate = account("끊겼던 사람");
        Room room = roomWith(owner, mate);

        send(owner, room.id(), "1번", "gap-1").andExpect(status().isCreated());
        long seen = lastSeqOf(messages(mate, room.id(), null, null));

        // 폴링이 끊긴 30초 — 실제로 네트워크를 끊는 대신 호출 사이에 메시지를 밀어넣는다.
        for (int i = 2; i <= 7; i++) {
            send(owner, room.id(), i + "번", "gap-" + i).andExpect(status().isCreated());
        }

        JsonNode delta = messages(mate, room.id(), seen, null);
        assertThat(bodies(delta))
                .as("끊긴 사이의 여섯 줄이 순서 그대로 와야 한다")
                .containsExactly("2번", "3번", "4번", "5번", "6번", "7번");
        assertThat(delta.path("lastSeq").asLong()).isEqualTo(7);
    }

    @Test
    @DisplayName("afterSeq 의 경계값 셋 — 0 · lastSeq · lastSeq 보다 큰 값")
    void afterSeqBoundaries() throws Exception {
        Account owner = account("보내는 사람");
        Room room = roomWith(owner);

        for (int i = 1; i <= 3; i++) {
            send(owner, room.id(), i + "번", "edge-" + i).andExpect(status().isCreated());
        }

        assertThat(bodies(messages(owner, room.id(), 0L, null)))
                .as("afterSeq=0 은 '아직 아무것도 못 받았다' 이고 전부를 뜻한다")
                .containsExactly("1번", "2번", "3번");
        assertThat(bodies(messages(owner, room.id(), 3L, null)))
                .as("afterSeq=lastSeq 는 빈 델타다 — 404 도 400 도 아니다")
                .isEmpty();
        JsonNode beyond = messages(owner, room.id(), 99L, null);
        assertThat(bodies(beyond))
                .as("lastSeq 보다 큰 afterSeq 도 빈 델타다. 앱의 커서가 앞서 있어도 500 이 아니다")
                .isEmpty();
        assertThat(beyond.path("lastSeq").asLong())
                .as("빈 응답에도 방의 현재 lastSeq 가 실려야 앱이 커서를 되맞출 수 있다")
                .isEqualTo(3);
    }

    @Test
    @DisplayName("삭제된 메시지도 델타에 톰스톤으로 들어온다 — 거르면 읽음 커서가 그 번호를 못 넘는다")
    void tombstonesStayInTheDelta() throws Exception {
        Account owner = account("보내는 사람");
        Room room = roomWith(owner);

        send(owner, room.id(), "남는 말", "tomb-1").andExpect(status().isCreated());
        send(owner, room.id(), "지워질 말", "tomb-2").andExpect(status().isCreated());
        send(owner, room.id(), "그 뒤의 말", "tomb-3").andExpect(status().isCreated());
        softDelete(room.id(), 2);

        JsonNode delta = messages(owner, room.id(), 0L, null);
        assertThat(seqs(delta))
                .as("""
                        톰스톤을 거르면 그 roomSeq 가 클라이언트에 도달하지 않아 읽음 커서가 그 번호를 \
                        넘지 못하고 미읽음 뱃지가 영원히 남는다 (ADR-0011).""")
                .containsExactly(1L, 2L, 3L);
        assertThat(delta.path("items").get(1).path("deletedAt").isNull())
                .as("톰스톤임을 앱이 알아야 본문을 가릴 수 있다")
                .isFalse();
    }

    @Test
    @DisplayName("limit 을 100000 으로 보내도 상한까지만 온다 — 거절이 아니라 자른다")
    void anAbsurdLimitIsCappedNotRejected() throws Exception {
        Account owner = account("보내는 사람");
        Room room = roomWith(owner);
        for (int i = 1; i <= 3; i++) {
            send(owner, room.id(), i + "번", "cap-" + i).andExpect(status().isCreated());
        }

        JsonNode page = messages(owner, room.id(), 0L, 100_000);
        assertThat(bodies(page)).containsExactly("1번", "2번", "3번");

        JsonNode oneAtATime = messages(owner, room.id(), 0L, 1);
        assertThat(bodies(oneAtATime)).containsExactly("1번");
        assertThat(oneAtATime.path("hasMore").asBoolean())
                .as("한 장을 다 채웠고 뒤가 남았으면 hasMore 가 참이어야 앱이 이어서 부른다")
                .isTrue();
    }

    // ─────────────────── 완료 조건 3 — 멱등 ───────────────────

    @Test
    @DisplayName("같은 clientMsgId 로 두 번 보내면 메시지는 1개고 두 응답의 roomSeq 가 같다 — 두 번째는 200")
    void resendingTheSameClientMsgIdIsIdempotent() throws Exception {
        Account owner = account("지하철에서 재시도한 사람");
        Room room = roomWith(owner);

        JsonNode first = body(send(owner, room.id(), "같은 말", "retry-1")
                .andExpect(status().isCreated()));
        JsonNode second = body(send(owner, room.id(), "같은 말", "retry-1")
                .andExpect(status().isOk()));

        assertThat(second.path("roomSeq").asLong())
                .as("""
                        재시도한 클라이언트 입장에서는 성공이다 — 409 가 아니다. \
                        UNIQUE (room_id, client_msg_id) 를 지우면 두 번째 INSERT 가 그냥 성공해 \
                        메시지가 2개가 되고 roomSeq 가 갈린다 (완료 조건 8).""")
                .isEqualTo(first.path("roomSeq").asLong());
        assertThat(second.path("id").asLong()).isEqualTo(first.path("id").asLong());
        assertThat(bodies(messages(owner, room.id(), 0L, null)))
                .as("메시지는 1개다")
                .containsExactly("같은 말");
        assertThat(roomInList(owner, room.id()).path("lastSeq").asLong())
                .as("거절된 두 번째 전송은 번호를 태우지 않는다 — 롤백이 발급을 되돌린다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("같은 방의 다른 멤버가 같은 clientMsgId 를 써도 둘 다 남는다 — 멱등의 범위는 보낸 사람까지다")
    void twoMembersUsingTheSameKeyDoNotEraseEachOther() throws Exception {
        Account first = account("첫째");
        Account second = account("둘째");
        Room room = roomWith(first, second);

        JsonNode mine = body(send(first, room.id(), "A 의 비밀 메모", "shared")
                .andExpect(status().isCreated()));
        JsonNode theirs = body(send(second, room.id(), "B 가 하려던 말", "shared")
                .andExpect(status().isCreated()));

        assertThat(theirs.path("body").asText())
                .as("""
                        범위가 (room_id, client_msg_id) 이던 판에서 이 요청은 200 과 함께 \
                        A 의 본문을 돌려줬다. B 의 앱은 200 을 성공으로 읽으므로 재시도하지 \
                        않고, B 가 하려던 말은 영영 사라진다.""")
                .isEqualTo("B 가 하려던 말");
        assertThat(theirs.path("senderUserId").asLong()).isEqualTo(second.id());
        assertThat(theirs.path("senderName").asText())
                .as("""
                        senderUserId 와 senderName 이 다른 사람을 가리키는 응답이 나가던 자리다 — \
                        컨트롤러가 언제나 부르는 사람의 이름을 찍는데 메시지는 남의 것이었다.""")
                .isEqualTo(nicknameOf(second));
        assertThat(theirs.path("roomSeq").asLong()).isNotEqualTo(mine.path("roomSeq").asLong());
        assertThat(bodies(messages(first, room.id(), 0L, null)))
                .as("두 줄 다 방에 남아야 한다")
                .containsExactly("A 의 비밀 메모", "B 가 하려던 말");

        assertThat(body(send(second, room.id(), "B 가 하려던 말", "shared")
                .andExpect(status().isOk())).path("roomSeq").asLong())
                .as("좁혔다고 해서 자기 자신의 재전송까지 풀리면 안 된다 — 완료 조건 3 은 그대로다")
                .isEqualTo(theirs.path("roomSeq").asLong());
    }

    @Test
    @DisplayName("같은 clientMsgId 가 동시에 두 번 와도 둘 다 200 대다 — 진 쪽이 500 이면 안 된다")
    void twoSendsWithTheSameKeyAtTheSameMomentBothSucceed() throws Exception {
        Account owner = account("두 번 동시에 누른 사람");
        Room room = roomWith(owner);

        List<Integer> statuses = new ArrayList<>();
        List<Long> assignedSeqs = new ArrayList<>();
        sendAtTheSameMoment(owner, room.id(), "동시에 같은 키", "race-1", 2, statuses, assignedSeqs);

        assertThat(statuses)
                .as("""
                        #75 에서 같은 자리가 500 으로 샜다 — 진 쪽이 Duplicate entry 를 그대로 \
                        받았고 GlobalExceptionHandler 의 catch-all 이 500 으로 내보냈다. \
                        계약은 이 경우를 멱등이라고 선언한다.""")
                .allMatch(status -> status == 200 || status == 201);
        assertThat(assignedSeqs)
                .as("둘이 같은 번호를 봐야 앱이 같은 말풍선을 두 개 그리지 않는다")
                .containsExactly(1L, 1L);
        assertThat(chatMessageRepository
                .findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(
                        room.id(), 0L, org.springframework.data.domain.Limit.of(10)))
                .as("메시지는 정확히 1개다")
                .hasSize(1);
    }

    @Test
    @DisplayName("clientMsgId 가 없는 전송은 멱등을 요구하지 않는다 — 같은 본문이라도 두 줄이다")
    void sendingWithoutAKeyIsNotDeduplicated() throws Exception {
        Account owner = account("키 없이 보내는 사람");
        Room room = roomWith(owner);

        send(owner, room.id(), "같은 말", null).andExpect(status().isCreated());
        send(owner, room.id(), "같은 말", null).andExpect(status().isCreated());

        assertThat(seqs(messages(owner, room.id(), 0L, null)))
                .as("멱등키가 없으면 서버가 같다고 볼 근거가 없다 — UNIQUE 는 NULL 을 겹침으로 보지 않는다")
                .containsExactly(1L, 2L);
    }

    // ─────────────────── 완료 조건 4 — 워터마크 ───────────────────

    @Test
    @DisplayName("last_read_seq=10 인 상태에서 seq=5 로 읽음을 보내면 10 이 유지된다 — GREATEST")
    void aLateReadReportCannotMoveTheWatermarkBackwards() throws Exception {
        Account owner = account("읽는 사람");
        Room room = roomWith(owner);
        for (int i = 1; i <= 10; i++) {
            send(owner, room.id(), i + "번", "read-" + i).andExpect(status().isCreated());
        }

        markRead(owner, room.id(), 10)
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.lastReadSeq").value(10))
                .andExpect(jsonPath("$.unread").value(0));

        JsonNode late = body(markRead(owner, room.id(), 5).andExpect(status().isOk()));
        assertThat(late.path("lastReadSeq").asLong())
                .as("""
                        읽음 보고는 재시도·백그라운드 복귀로 순서가 뒤집혀 도착한다. GREATEST 를 \
                        단순 대입으로 되돌리면 여기가 5 가 되고, 이미 읽은 다섯 줄이 다시 \
                        미읽음으로 뜬다 (완료 조건 7).""")
                .isEqualTo(10);
        assertThat(late.path("unread").asLong()).isZero();
        assertThat(roomInList(owner, room.id()).path("lastReadSeq").asLong()).isEqualTo(10);
    }

    @Test
    @DisplayName("방의 lastSeq 보다 큰 값으로 읽음을 보내면 잘린다 — 미읽음이 음수가 되지 않는다")
    void aReadReportBeyondTheRoomIsClampedSoUnreadNeverGoesNegative() throws Exception {
        Account owner = account("앞서간 사람");
        Room room = roomWith(owner);
        send(owner, room.id(), "하나뿐인 말", "clamp-1").andExpect(status().isCreated());

        JsonNode ahead = body(markRead(owner, room.id(), 999).andExpect(status().isOk()));
        assertThat(ahead.path("lastReadSeq").asLong())
                .as("LEAST(:seq, room.last_seq) 가 없으면 워터마크가 999 가 된다")
                .isEqualTo(1);
        assertThat(ahead.path("unread").asLong())
                .as("그리고 미읽음이 1 - 999 = -998 이 된다. 뱃지에 음수가 뜬다")
                .isZero();
        assertThat(roomInList(owner, room.id()).path("unread").asLong()).isZero();
    }

    @Test
    @DisplayName("읽음 값이 없거나 음수면 400 이고 워터마크는 그대로다")
    void anInvalidReadReportIsRejected() throws Exception {
        Account owner = account("이상한 값을 보낸 사람");
        Room room = roomWith(owner);
        send(owner, room.id(), "한 줄", "bad-1").andExpect(status().isCreated());
        markRead(owner, room.id(), 1).andExpect(status().isOk());

        mockMvc.perform(post("/api/chat/rooms/{roomId}/read", room.id())
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("VALIDATION"));
        markRead(owner, room.id(), -1)
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("VALIDATION"));

        assertThat(roomInList(owner, room.id()).path("lastReadSeq").asLong()).isEqualTo(1);
    }

    // ─────────────────── 신고 (이슈 #82) ───────────────────

    @Test
    @DisplayName("신고가 201 이고 응답에는 접수 번호와 시각뿐이다 — 피신고자 id 도 안 준다")
    void reportingReturnsNothingButAReceipt() throws Exception {
        Account reporter = account("신고하는 사람");
        Account troll = account("신고당하는 사람");
        Room room = roomWith(reporter, troll);
        send(troll, room.id(), "여기서 하면 안 되는 말", "bad-1").andExpect(status().isCreated());

        String body = mockMvc.perform(post("/api/chat/rooms/{roomId}/reports", room.id())
                        .header("Authorization", "Bearer " + reporter.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"roomSeqs\":[1],\"reason\":\"abuse\",\"memo\":\"욕설입니다\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.reportId").isNumber())
                .andExpect(jsonPath("$.createdAt").isString())
                .andReturn().getResponse().getContentAsString();

        assertThat(body)
                .as("""
                        신고에 성공한 쪽은 이미 누구를 왜 신고했는지 안다. 서버가 그것을 되돌려
                        줄 이유가 없고, 되돌려 주면 응답이 그 자체로 유출 경로가 된다.
                        """)
                .doesNotContain(String.valueOf(troll.id()))
                .doesNotContain("reporter")
                .doesNotContain("body")
                .doesNotContain("senderName");
    }

    @Test
    @DisplayName("사유가 계약의 목록에 없으면 400 이고 코드가 갈린다")
    void anUnknownReasonIsFourHundred() throws Exception {
        Account reporter = account("사유를 틀린 사람");
        Account troll = account("신고당할 사람");
        Room room = roomWith(reporter, troll);
        send(troll, room.id(), "말", "bad-2").andExpect(status().isCreated());

        mockMvc.perform(post("/api/chat/rooms/{roomId}/reports", room.id())
                        .header("Authorization", "Bearer " + reporter.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"roomSeqs\":[1],\"reason\":\"harrassment\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("REPORT_REASON_UNKNOWN"))
                .andExpect(jsonPath("$.error.traceId").exists());
    }

    @Test
    @DisplayName("남의 방은 신고도 못 한다 — 방 존재 여부가 여기로 새면 안 된다")
    void reportingSomeoneElsesRoomIsForbidden() throws Exception {
        Account owner = account("남의 방장");
        Account mate = account("남의 멤버");
        Account outsider = account("바깥사람");
        Room theirs = roomWith(owner, mate);
        send(mate, theirs.id(), "우리끼리 하는 말", "bad-3").andExpect(status().isCreated());

        mockMvc.perform(post("/api/chat/rooms/{roomId}/reports", theirs.id())
                        .header("Authorization", "Bearer " + outsider.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"roomSeqs\":[1],\"reason\":\"abuse\"}"))
                .andExpect(status().isForbidden());
    }

    // ─────────────────── 완료 조건 5·6·9 — 인가 ───────────────────

    @Test
    @DisplayName("남의 방 id 로 부르면 셋 다 403 이고, 응답 어디에도 그 방의 이름·멤버·메시지가 없다")
    void someoneElsesRoomIsForbiddenAndLeaksNothing() throws Exception {
        Account owner = account("남의 가족 방장");
        Account mate = account("남의 가족 멤버");
        Room theirs = roomWith(owner, mate);
        send(owner, theirs.id(), "우리끼리 하는 말", "secret-1").andExpect(status().isCreated());

        Account outsider = account("아무 상관 없는 사람");

        assertHidesEverything(theirs, owner, mate,
                mockMvc.perform(get("/api/chat/rooms/{roomId}/messages", theirs.id())
                        .header("Authorization", "Bearer " + outsider.token())));
        assertHidesEverything(theirs, owner, mate,
                send(outsider, theirs.id(), "끼어드는 말", "intrude-1"));
        assertHidesEverything(theirs, owner, mate, markRead(outsider, theirs.id(), 1));

        MockHttpServletResponse list = mockMvc.perform(get("/api/chat/rooms")
                        .header("Authorization", "Bearer " + outsider.token()))
                .andExpect(status().isOk())
                .andReturn().getResponse();
        assertThat(list.getContentAsString(StandardCharsets.UTF_8))
                .as("""
                        방 목록에는 roomId 를 실을 자리가 없어 403 을 낼 대상이 없다. 대신 남의 방이 \
                        목록에 섞이지 않는 것이 같은 요구다 — 멤버십 검사를 지우면 여기가 빨간불이다.""")
                .doesNotContain(theirs.title())
                .doesNotContain("우리끼리 하는 말")
                .doesNotContain(String.valueOf(theirs.id()));

        assertThat(chatMessageRepository.findByRoomIdAndSenderUserIdAndClientMsgId(
                        theirs.id(), outsider.id(), "intrude-1"))
                .as("403 이 난 전송이 행을 남기면 인가가 아니라 필터일 뿐이다")
                .isEmpty();
    }

    @Test
    @DisplayName("존재하지 않는 방과 권한 없는 방이 같은 응답이다 — 다르면 방 id 를 훑어 가려낼 수 있다")
    void anUnknownRoomAndAForbiddenRoomAnswerTheSameThing() throws Exception {
        Account owner = account("방장");
        Room theirs = roomWith(owner);
        Account outsider = account("훑어보는 사람");

        long noSuchRoom = theirs.id() + 10_000;
        String forbidden = payloadOf(mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", theirs.id())
                        .header("Authorization", "Bearer " + outsider.token()))
                .andExpect(status().isForbidden()));
        String unknown = payloadOf(mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", noSuchRoom)
                        .header("Authorization", "Bearer " + outsider.token()))
                .andExpect(status().isForbidden()));

        assertThat(scrub(unknown))
                .as("""
                        404 로 답하면 방 id 를 1부터 훑어 '있는 방/없는 방' 을 가려낼 수 있다. \
                        방 존재 여부는 그 방 멤버에게만 의미가 있는 정보다 \
                        (ChatRoomService.requireOwner 가 이미 그 판단을 했다).""")
                .isEqualTo(scrub(forbidden));
    }

    @Test
    @DisplayName("강퇴된(removed_at 이 찍힌) 계정이 같은 방을 부르면 403 이다 — 세 경로 전부")
    void aRemovedMemberIsForbiddenEverywhere() throws Exception {
        Account owner = account("방장");
        Account removed = account("강퇴당한 사람");
        Room room = roomWith(owner, removed);
        send(owner, room.id(), "쫓겨나기 전의 말", "kick-1").andExpect(status().isCreated());

        // 강퇴 엔드포인트는 M2.7 이다. 지금 정하는 것은 "그 표식이 찍혀 있으면 어떻게 되는가" 하나다.
        ChatRoomMember row = chatRoomMemberRepository
                .findByRoomIdAndUserId(room.id(), removed.id()).orElseThrow();
        row.setRemovedAt(LocalDateTime.now());
        row.setRemovedBy(owner.id());
        chatRoomMemberRepository.saveAndFlush(row);

        mockMvc.perform(get("/api/chat/rooms/{roomId}/messages", room.id())
                        .header("Authorization", "Bearer " + removed.token()))
                .andExpect(status().isForbidden());
        send(removed, room.id(), "그래도 보내는 말", "kick-2").andExpect(status().isForbidden());
        markRead(removed, room.id(), 1).andExpect(status().isForbidden());

        assertThat(payloadOf(mockMvc.perform(get("/api/chat/rooms")
                        .header("Authorization", "Bearer " + removed.token()))
                .andExpect(status().isOk())))
                .as("강퇴된 사람의 방 목록에서도 그 방이 빠져야 한다")
                .doesNotContain(room.title());
    }

    @Test
    @DisplayName("토큰 없이 부르면 네 경로가 전부 401 이고 본문이 없다")
    void withoutAToken_everyNewEndpointIs401() throws Exception {
        assertUnauthorized(get("/api/chat/rooms"));
        assertUnauthorized(get("/api/chat/rooms/{roomId}/messages", 1));
        assertUnauthorized(post("/api/chat/rooms/{roomId}/messages", 1)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"body\":\"x\",\"clientMsgId\":\"y\"}"));
        assertUnauthorized(post("/api/chat/rooms/{roomId}/read", 1)
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"lastReadSeq\":1}"));
    }

    // ─────────────────── ETag ───────────────────

    @Test
    @DisplayName("새 메시지가 없으면 If-None-Match 가 304 다. 하나 오면 200 이고 ETag 가 바뀐다")
    void pollingWithAnUnchangedEtagIs304() throws Exception {
        Account owner = account("보내는 사람");
        Account poller = account("폴링하는 사람");
        Room room = roomWith(owner, poller);
        send(owner, room.id(), "첫 줄", "etag-1").andExpect(status().isCreated());

        MockHttpServletResponse first = mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("afterSeq", "0")
                        .header("Authorization", "Bearer " + poller.token()))
                .andExpect(status().isOk())
                .andReturn().getResponse();
        String etag = first.getHeader("ETag");
        assertThat(etag).isEqualTo("\"%d:1\"".formatted(room.id()));

        MockHttpServletResponse unchanged = mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("afterSeq", "1")
                        .header("If-None-Match", etag)
                        .header("Authorization", "Bearer " + poller.token()))
                .andExpect(status().isNotModified())
                .andReturn().getResponse();
        assertThat(unchanged.getContentAsString(StandardCharsets.UTF_8))
                .as("304 는 본문을 싣지 않는다 — 그게 이 최적화의 전부다")
                .isEmpty();

        send(owner, room.id(), "둘째 줄", "etag-2").andExpect(status().isCreated());

        MockHttpServletResponse changed = mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("afterSeq", "1")
                        .header("If-None-Match", etag)
                        .header("Authorization", "Bearer " + poller.token()))
                .andExpect(status().isOk())
                .andReturn().getResponse();
        assertThat(changed.getHeader("ETag")).isEqualTo("\"%d:2\"".formatted(room.id()));
        assertThat(changed.getContentAsString(StandardCharsets.UTF_8)).contains("둘째 줄");
    }

    @Test
    @DisplayName("남의 방 ETag 를 들고 와도 304 가 아니라 403 이다 — 304/200 차이가 오라클이 된다")
    void anOutsiderCannotProbeLastSeqWithAnEtag() throws Exception {
        Account owner = account("방장");
        Room theirs = roomWith(owner);
        send(owner, theirs.id(), "한 줄", "probe-1").andExpect(status().isCreated());
        Account outsider = account("탐색하는 사람");

        mockMvc.perform(get("/api/chat/rooms/{roomId}/messages", theirs.id())
                        .param("afterSeq", "1")
                        .header("If-None-Match", "\"%d:1\"".formatted(theirs.id()))
                        .header("Authorization", "Bearer " + outsider.token()))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("한 장을 못 채운 첫 장의 ETag 를 들고 이어서 폴링해도 다음 장이 온다 — 완료 조건 2")
    void catchingUpAcrossTwoPagesLosesNothing() throws Exception {
        Account owner = account("쌓는 사람");
        Account poller = account("30초 끊겼던 사람");
        Room room = roomWith(owner, poller);
        for (int i = 1; i <= 60; i++) {
            send(owner, room.id(), i + "번", "catchup-" + i).andExpect(status().isCreated());
        }

        MockHttpServletResponse firstPage = mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("afterSeq", "0")
                        .header("Authorization", "Bearer " + poller.token()))
                .andExpect(status().isOk())
                .andReturn().getResponse();
        JsonNode page = MAPPER.readTree(firstPage.getContentAsString(StandardCharsets.UTF_8));
        assertThat(page.path("items").size()).isEqualTo(50);
        assertThat(page.path("hasMore").asBoolean()).isTrue();
        assertThat(firstPage.getHeader("ETag"))
                .as("""
                        이 응답은 60번까지 준 적이 없다. 그런데 "이 응답은 lastSeq=60 상태다" 라고 \
                        표시하면 그건 거짓말이고, 스프링 MVC 가 다음 요청에서 그 값을 대조해 \
                        200 을 빈 304 로 갈아치운다 — 51~60 열 줄이 사라진다.""")
                .isNull();

        // 계약이 시키는 대로 이어서 부른다 — 직전 응답이 준 ETag 를 되보내고, 커서는
        // 마지막으로 받은 번호로. 여기서 손으로 값을 지어내지 않는 것이 요점이다:
        // 옛 판은 이 자리에서 "1:60" 을 돌려줬고, 그것을 그대로 되보내면 304 가 됐다.
        MockHttpServletRequestBuilder resume = get("/api/chat/rooms/{roomId}/messages", room.id())
                .param("afterSeq", "50")
                .header("Authorization", "Bearer " + poller.token());
        if (firstPage.getHeader("ETag") != null) {
            resume = resume.header("If-None-Match", firstPage.getHeader("ETag"));
        }
        MockHttpServletResponse secondPage = mockMvc.perform(resume).andReturn().getResponse();

        assertThat(secondPage.getStatus())
                .as("""
                        여기가 304 면 방 목록의 미읽음 뱃지는 60 을 가리키는데 방을 열면 아무것도 \
                        새로 안 뜬다. 다음 새 메시지가 lastSeq 를 바꾸기 전까지 복구되지 않는다.""")
                .isEqualTo(200);
        assertThat(seqs(MAPPER.readTree(secondPage.getContentAsString(StandardCharsets.UTF_8))))
                .containsExactly(51L, 52L, 53L, 54L, 55L, 56L, 57L, 58L, 59L, 60L);
    }

    @Test
    @DisplayName("옛 ETag 를 들고 첫 진입하거나 과거를 스크롤해도 304 가 아니다 — 304 는 폴링에만 나간다")
    void anOldEtagDoesNotBlockTheFirstScreenOrScrollback() throws Exception {
        Account owner = account("쌓는 사람");
        Account reader = account("다시 들어온 사람");
        Room room = roomWith(owner, reader);
        for (int i = 1; i <= 3; i++) {
            send(owner, room.id(), i + "번", "entry-" + i).andExpect(status().isCreated());
        }
        // 폴링으로 따라잡아 ETag 를 손에 넣는다. 지어낸 값이 아니라 서버가 준 값이다.
        String currentEtag = mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("afterSeq", "0")
                        .header("Authorization", "Bearer " + reader.token()))
                .andExpect(status().isOk())
                .andReturn().getResponse().getHeader("ETag");
        assertThat(currentEtag)
                .as("한 장에 다 담긴 폴링 응답은 '이제 lastSeq 까지 전부 받았다' 라 ETag 가 붙는다")
                .isEqualTo("\"%d:3\"".formatted(room.id()));

        MockHttpServletResponse firstScreen = mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", room.id())
                        .header("If-None-Match", currentEtag)
                        .header("Authorization", "Bearer " + reader.token()))
                .andReturn().getResponse();
        MockHttpServletResponse scrollback = mockMvc.perform(
                get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("beforeSeq", "3")
                        .header("If-None-Match", currentEtag)
                        .header("Authorization", "Bearer " + reader.token()))
                .andReturn().getResponse();

        assertThat(firstScreen.getStatus())
                .as("""
                        계약은 "304 는 afterSeq 를 보낸 폴링 요청에만 나갑니다" 라고 적었는데 \
                        옛 판에서는 둘 다 빈 304 였다 — 앱은 대화를 한 줄도 못 그린다.""")
                .isEqualTo(200);
        assertThat(scrollback.getStatus()).isEqualTo(200);
        assertThat(bodies(MAPPER.readTree(
                firstScreen.getContentAsString(StandardCharsets.UTF_8))))
                .containsExactly("1번", "2번", "3번");
    }

    // ─────────────────── 계약에 없는 500 을 내지 않는다 ───────────────────

    @Test
    @DisplayName("숫자가 아닌 roomId·afterSeq·limit 은 500 이 아니라 400 이다 — 폴링이 재시도 루프를 돌면 안 된다")
    void malformedCursorsAre400NotInternalError() throws Exception {
        Account owner = account("커서가 깨진 사람");
        Room room = roomWith(owner);
        String auth = "Bearer " + owner.token();

        record Case(String label, MockHttpServletRequestBuilder request) { }
        List<Case> cases = List.of(
                new Case("afterSeq=abc", get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("afterSeq", "abc")),
                new Case("limit=abc", get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("limit", "abc")),
                new Case("limit=1.5", get("/api/chat/rooms/{roomId}/messages", room.id())
                        .param("limit", "1.5")),
                new Case("afterSeq 가 long 범위를 넘음",
                        get("/api/chat/rooms/{roomId}/messages", room.id())
                                .param("afterSeq", "99999999999999999999")),
                new Case("roomId=abc", get("/api/chat/rooms/abc/messages")),
                new Case("read 의 roomId=abc", post("/api/chat/rooms/abc/read")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"lastReadSeq\":1}")));

        for (Case testCase : cases) {
            MockHttpServletResponse response = mockMvc
                    .perform(testCase.request().header("Authorization", auth))
                    .andReturn().getResponse();
            String payload = response.getContentAsString(StandardCharsets.UTF_8);

            assertThat(response.getStatus())
                    .as("""
                            %s — 계약은 이 경로에 400·401·403 만 선언한다. 500 은 앱에게 \
                            "서버 고장이니 재시도하라" 는 뜻이고, 이 넷은 rate limit 표 밖이라 \
                            한도가 무한이다. 커서가 한 번 오염되면 그대로 무한 재시도다.""",
                            testCase.label())
                    .isEqualTo(400);
            assertThat(MAPPER.readTree(payload).path("error").path("code").asText())
                    .isEqualTo("VALIDATION");
            // traceId 는 16진수 UUID 라 "abc" 를 우연히 품을 수 있다. 그 자리를 지우고 본다.
            assertThat(scrub(payload))
                    .as("예외 메시지에는 들어온 값이 그대로 섞여 있다 — For input string: \"abc\" (#6)")
                    .doesNotContain("abc")
                    .doesNotContain("1.5")
                    .doesNotContain("99999999999999999999");
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private record Room(long id, String title) { }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("chat79-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /**
     * 방 하나와 멤버들. <b>가족 그룹을 거치지 않는다</b> — 방은 범용이고(ADR-0011) 이 이슈가
     * 재는 것은 방 자체의 인가·델타·워터마크다.
     *
     * <p>멤버를 넣는 것도 초대코드 경로(#75)를 그대로 쓴다. 멤버십 행을 손으로 만들면
     * {@code role}·{@code last_read_seq} 기본값을 테스트가 다시 정하게 되고, 그러면 이
     * 테스트가 재는 것이 실제 입장 경로가 만든 상태가 아니게 된다.
     */
    private Room roomWith(Account owner, Account... others) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        String title = "방-%d-%d".formatted(System.nanoTime(), serial);
        ChatRoomView room = chatRooms.openRoom(
                "CHAT79_TEST", String.valueOf(serial), title, "테스트", owner.id());
        for (Account other : others) {
            String code = chatRooms.issueInvite(room.id(), owner.id()).code();
            chatRooms.joinByInviteCode(code, other.id());
        }
        return new Room(room.id(), title);
    }

    private ResultActions send(Account account, long roomId, String text, String clientMsgId)
            throws Exception {
        String payload = clientMsgId == null
                ? "{\"body\":\"%s\"}".formatted(text)
                : "{\"body\":\"%s\",\"clientMsgId\":\"%s\"}".formatted(text, clientMsgId);
        return mockMvc.perform(post("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(payload));
    }

    private ResultActions markRead(Account account, long roomId, long seq) throws Exception {
        return mockMvc.perform(post("/api/chat/rooms/{roomId}/read", roomId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"lastReadSeq\":%d}".formatted(seq)));
    }

    private JsonNode messages(Account account, long roomId, Long afterSeq, Integer limit)
            throws Exception {
        MockHttpServletRequestBuilder request =
                get("/api/chat/rooms/{roomId}/messages", roomId)
                        .header("Authorization", "Bearer " + account.token());
        if (afterSeq != null) {
            request = request.param("afterSeq", String.valueOf(afterSeq));
        }
        if (limit != null) {
            request = request.param("limit", String.valueOf(limit));
        }
        return body(mockMvc.perform(request).andExpect(status().isOk()));
    }

    /** 내 방 목록에서 이 방 하나. 없으면 실패한다. */
    private JsonNode roomInList(Account account, long roomId) throws Exception {
        JsonNode rooms = body(mockMvc.perform(get("/api/chat/rooms")
                        .header("Authorization", "Bearer " + account.token()))
                .andExpect(status().isOk()));
        for (JsonNode room : rooms) {
            if (room.path("id").asLong() == roomId) {
                return room;
            }
        }
        throw new AssertionError("방 목록에 " + roomId + " 이 없다: " + rooms);
    }

    /** 소프트 삭제 — 삭제 엔드포인트는 M2.6 의 다른 이슈다. 여기서는 표식만 찍는다. */
    private void softDelete(long roomId, long roomSeq) {
        ChatMessage message = chatMessageRepository
                .findByRoomIdAndRoomSeqGreaterThanOrderByRoomSeqAsc(
                        roomId, roomSeq - 1, org.springframework.data.domain.Limit.of(1))
                .get(0);
        message.setDeletedAt(LocalDateTime.now());
        chatMessageRepository.saveAndFlush(message);
    }

    /**
     * 같은 멱등키로 여러 요청을 <b>실제로 같은 순간에</b> 출발시킨다.
     *
     * <p>순차 재요청만 보는 테스트는 이 경로를 정의상 지나지 않는다 — 진 쪽이
     * {@code DataIntegrityViolationException} 을 받는 자리가 여기다.
     */
    private void sendAtTheSameMoment(Account account, long roomId, String text, String clientMsgId,
                                     int howMany, List<Integer> statusesOut,
                                     List<Long> seqsOut) throws Exception {
        CyclicBarrier startLine = new CyclicBarrier(howMany);
        int[] statuses = new int[howMany];
        long[] seqs = new long[howMany];
        List<Thread> threads = new ArrayList<>();

        for (int i = 0; i < howMany; i++) {
            final int index = i;
            Thread thread = new Thread(() -> {
                try {
                    startLine.await();
                    MockHttpServletResponse response =
                            send(account, roomId, text, clientMsgId).andReturn().getResponse();
                    statuses[index] = response.getStatus();
                    seqs[index] = MAPPER.readTree(
                                    response.getContentAsString(StandardCharsets.UTF_8))
                            .path("roomSeq").asLong(-1);
                } catch (Exception thrown) {
                    statuses[index] = -1;
                    seqs[index] = -1;
                }
            });
            threads.add(thread);
            thread.start();
        }
        for (Thread thread : threads) {
            thread.join();
        }
        for (int i = 0; i < howMany; i++) {
            statusesOut.add(statuses[i]);
            seqsOut.add(seqs[i]);
        }
    }

    /**
     * 403 이면서 <b>본문 어디에도</b> 그 방의 이름·멤버 이름·메시지가 없다 — 완료 조건 5.
     *
     * <p>상태 코드만 보는 테스트는 절반만 잠근다. 응답 본문을 실제로 뒤진다.
     */
    private void assertHidesEverything(Room room, Account owner, Account mate, ResultActions actions)
            throws Exception {
        String payload = payloadOf(actions.andExpect(status().isForbidden()));
        assertThat(payload)
                .as("방 이름·멤버 이름·메시지 본문 중 하나라도 새면 403 은 형식일 뿐이다 (#6)")
                .doesNotContain(room.title())
                .doesNotContain("우리끼리 하는 말")
                .doesNotContain(nicknameOf(owner))
                .doesNotContain(nicknameOf(mate));
        assertThat(MAPPER.readTree(payload).path("error").path("code").asText())
                .isEqualTo("FORBIDDEN");
    }

    private String nicknameOf(Account account) {
        return userRepository.findById(account.id()).orElseThrow().getNickname();
    }

    /** traceId 는 요청마다 다르다 — 두 응답을 비교하기 전에 그 자리를 지운다. */
    private static String scrub(String payload) {
        return payload.replaceAll("\"traceId\"\\s*:\\s*(\"[^\"]*\"|null)", "\"traceId\":\"*\"");
    }

    private void assertUnauthorized(MockHttpServletRequestBuilder request) throws Exception {
        MockHttpServletResponse response = mockMvc.perform(request)
                .andExpect(status().isUnauthorized())
                .andReturn().getResponse();

        assertThat(response.getContentAsString(StandardCharsets.UTF_8))
                .as("401 은 본문이 없다 — 원인을 실으면 그게 유출 경로다 (#5·#6)")
                .isEmpty();
    }

    private static List<String> bodies(JsonNode page) {
        List<String> result = new ArrayList<>();
        for (JsonNode item : page.path("items")) {
            result.add(item.path("body").asText());
        }
        return result;
    }

    private static List<Long> seqs(JsonNode page) {
        List<Long> result = new ArrayList<>();
        for (JsonNode item : page.path("items")) {
            result.add(item.path("roomSeq").asLong());
        }
        return result;
    }

    private static long lastSeqOf(JsonNode page) {
        return page.path("lastSeq").asLong();
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(payloadOf(actions));
    }

    private static String payloadOf(ResultActions actions) throws Exception {
        return actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
    }
}
