package com.heattrip.heat_trip_backend.chat;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 말풍선 아래 반응 — #452, ADR-0023(#500) 셋째 줄. <b>HTTP 로</b> 확인한다.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>남이 누른 반응이 내 폴링에 오는가.</b> 반응은 {@code room_seq} 를 올리지 않으므로 델타만으로는
 * 영영 오지 않는다 — 변경 피드(ADR-0023)를 타야 온다. 그러면서도 <b>새 메시지는 아니어야 한다</b>:
 * 미읽음이 늘면 방마다 빨간 점이 붙고, 그건 반응을 "누르면 상대를 부르는 것" 으로 만든다.
 *
 * <p>그다음이 멱등이다. 켜기·끄기가 따로라 재시도가 반응을 되돌리지 않는다 — 커뮤니티 반응이
 * 2026-09 에 토글을 버린 이유가 그것이다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄뿐인 것은 의도다 —
 * 다른 채팅 통합 테스트와 글자 그대로 같아야 스프링 컨텍스트 캐시를 공유한다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
class ChatReactionIntegrationTest extends AbstractMySqlIntegrationTest {

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

    // ─────────────────── 멱등 ───────────────────

    @Test
    @DisplayName("두 번 눌러도 하나다 — 응답은 최신 집계이고 mine 이 켜져 있다")
    void pressingTwiceCountsOnce() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);
        long messageId = idOf(send(owner, room.id(), "보리 밥 줬어요"));

        JsonNode first = body(react(mate, messageId, "like").andExpect(status().isOk()));
        JsonNode again = body(react(mate, messageId, "like").andExpect(status().isOk()));

        assertThat(first.path("messageId").asLong())
                .as("응답만 들고도 어느 말풍선에 얹을지 알아야 한다")
                .isEqualTo(messageId);
        assertThat(count(again, "like"))
                .as("""
                        네트워크 재시도 한 번에 숫자가 둘이 되면, 앱은 재시도를 못 하고 사용자는 \
                        자기가 두 번 누른 줄 안다. 멱등을 딛는 것은 uq_chat_reaction 이다.""")
                .isEqualTo(1);
        assertThat(again.path("reactions").get(0).path("mine").asBoolean()).isTrue();
    }

    @Test
    @DisplayName("안 눌렀던 것을 취소해도 200 이다 — 없던 것과 있던 것을 상태 코드로 가르지 않는다")
    void cancellingSomethingNeverPressedIsStillOk() throws Exception {
        Account owner = account("보리아빠");
        Room room = roomWith(owner);
        long messageId = idOf(send(owner, room.id(), "혼잣말"));

        JsonNode empty = body(unreact(owner, messageId, "heart").andExpect(status().isOk()));

        assertThat(empty.path("reactions")).isEmpty();
    }

    @Test
    @DisplayName("한 사람이 한 말에 여러 종류를 누를 수 있다 — 순서는 서버가 정한다")
    void onePersonCanPressSeveralKinds() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);
        long messageId = idOf(send(owner, room.id(), "보리 산책 다녀왔어요"));

        react(mate, messageId, "check").andExpect(status().isOk());
        react(mate, messageId, "laugh").andExpect(status().isOk());
        JsonNode after = body(react(mate, messageId, "like").andExpect(status().isOk()));

        assertThat(kinds(after))
                .as("""
                        유니크가 (message, user, kind) 셋이라 라디오가 아니다. 순서를 앱에 맡기면 \
                        같은 말이 기기마다 다르게 그려지므로 서버가 REACTION_KINDS 순서로 낸다.""")
                .containsExactly("like", "laugh", "check");

        JsonNode left = body(unreact(mate, messageId, "laugh").andExpect(status().isOk()));
        assertThat(kinds(left)).containsExactly("like", "check");
    }

    // ─────────────────── 변경 피드 (ADR-0023) ───────────────────

    @Test
    @DisplayName("남이 누른 반응이 내 폴링에 changed 로 온다 — 새 말은 하나도 없다")
    void someoneElsesReactionArrivesThroughTheChangeFeed() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);
        long messageId = idOf(send(owner, room.id(), "보리 밥 줬어요"));

        JsonNode firstPoll = poll(owner, room.id(), 0L, null);
        long lastChangeSeq = firstPoll.path("lastChangeSeq").asLong();
        long lastSeq = firstPoll.path("lastSeq").asLong();

        react(mate, messageId, "heart").andExpect(status().isOk());

        JsonNode second = poll(owner, room.id(), lastSeq, lastChangeSeq);
        assertThat(second.path("items"))
                .as("반응은 새 말이 아니다 — items 에 오면 앱이 대화 맨 아래에 같은 말을 또 그린다")
                .isEmpty();
        assertThat(second.path("changed")).hasSize(1);
        JsonNode changed = second.path("changed").get(0);
        assertThat(changed.path("id").asLong()).isEqualTo(messageId);
        assertThat(changed.path("roomSeq").asLong())
                .as("room_seq 를 다시 발급하면 오래된 말이 대화 맨 아래로 뛴다(ADR-0011 결정 2)")
                .isEqualTo(lastSeq);
        assertThat(count(changed, "heart")).isEqualTo(1);
        assertThat(changed.path("reactions").get(0).path("mine").asBoolean())
                .as("누른 사람은 mate 다 — 같은 값이 사람마다 다르다")
                .isFalse();
        assertThat(second.path("lastChangeSeq").asLong()).isGreaterThan(lastChangeSeq);
    }

    @Test
    @DisplayName("반응은 미읽음을 올리지 않는다 — 누르는 것은 부르는 것이 아니다")
    void reactingDoesNotRaiseTheUnreadBadge() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);
        long messageId = idOf(send(owner, room.id(), "보리 밥 줬어요"));
        long before = roomInList(owner, room.id()).path("unread").asLong();

        react(mate, messageId, "like").andExpect(status().isOk());

        assertThat(roomInList(owner, room.id()).path("unread").asLong())
                .as("미읽음은 lastSeq − lastReadSeq 뺄셈이고 반응은 lastSeq 를 안 건드린다")
                .isEqualTo(before);
    }

    @Test
    @DisplayName("반응이 붙으면 ETag 가 달라진다 — 304 가 변화를 가리지 않는다")
    void theEtagMovesSoThatPollingCannotMissIt() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);
        long messageId = idOf(send(owner, room.id(), "보리 밥 줬어요"));

        ResultActions first = mockMvc.perform(pollRequest(owner, room.id(), 0L, null))
                .andExpect(status().isOk());
        String etag = first.andReturn().getResponse().getHeader(HttpHeaders.ETAG);
        long lastSeq = body(first).path("lastSeq").asLong();
        long lastChangeSeq = body(first).path("lastChangeSeq").asLong();

        mockMvc.perform(pollRequest(owner, room.id(), lastSeq, lastChangeSeq)
                        .header(HttpHeaders.IF_NONE_MATCH, etag))
                .andExpect(status().isNotModified());

        react(mate, messageId, "like").andExpect(status().isOk());

        ResultActions afterReaction = mockMvc.perform(
                        pollRequest(owner, room.id(), lastSeq, lastChangeSeq)
                                .header(HttpHeaders.IF_NONE_MATCH, etag))
                .andExpect(status().isOk());
        assertThat(afterReaction.andReturn().getResponse().getHeader(HttpHeaders.ETAG))
                .as("ETag 가 lastChangeSeq 를 담으므로 값이 달라진다 — 담지 않으면 304 가 거짓말을 한다")
                .isNotEqualTo(etag);
        assertThat(body(afterReaction).path("changed")).hasSize(1);
    }

    // ─────────────────── 인가 · 지워진 말 · 모르는 종류 ───────────────────

    @Test
    @DisplayName("그 방 사람이 아니면 403 이다 — 없는 방과 남의 방이 같은 답이다")
    void strangersCannotReact() throws Exception {
        Account owner = account("보리아빠");
        Account stranger = account("남");
        Room room = roomWith(owner);
        long messageId = idOf(send(owner, room.id(), "우리끼리 이야기"));

        react(stranger, messageId, "like").andExpect(status().isForbidden());
        unreact(stranger, messageId, "like").andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("지운 말은 반응을 잃고, 거기에 새로 누르면 409 다 — 취소는 그래도 200")
    void deletingAMessageTakesItsReactionsAway() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);
        long messageId = idOf(send(owner, room.id(), "이건 곧 지울게요"));
        react(mate, messageId, "like").andExpect(status().isOk());

        mockMvc.perform(delete("/api/chat/messages/{messageId}", messageId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNoContent());

        JsonNode page = poll(mate, room.id(), 0L, null);
        JsonNode tombstone = page.path("items").get(0);
        assertThat(tombstone.path("deletedAt").isNull()).isFalse();
        assertThat(tombstone.path("reactions"))
                .as("""
                        지운 말 밑에 "1명이 좋아요" 가 남으면 지운 사람에게는 지워지지 않은 것이나 같다. \
                        FK 의 CASCADE 는 하드 삭제에만 돌아서 서버가 직접 거둔다.""")
                .isEmpty();

        react(mate, messageId, "like").andExpect(status().isConflict());
        unreact(mate, messageId, "like")
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("모르는 종류는 400 이다 — 표에 CHECK 가 없으니 이 문이 유일하다")
    void unknownKindsAreRefused() throws Exception {
        Account owner = account("보리아빠");
        Room room = roomWith(owner);
        long messageId = idOf(send(owner, room.id(), "혼잣말"));

        react(owner, messageId, "shrug").andExpect(status().isBadRequest());
        assertThat(poll(owner, room.id(), 0L, null).path("items").get(0).path("reactions"))
                .as("모르는 문자열이 들어가면 말풍선 아래에 남이 만든 아무 글자나 뜬다")
                .isEmpty();
    }

    @Test
    @DisplayName("mine 은 읽는 사람마다 다르다 — 같은 말, 같은 집계, 다른 값")
    void mineIsPerViewer() throws Exception {
        Account owner = account("보리아빠");
        Account mate = account("보리엄마");
        Room room = roomWith(owner, mate);
        long messageId = idOf(send(owner, room.id(), "보리 밥 줬어요"));
        react(mate, messageId, "check").andExpect(status().isOk());

        JsonNode forMate = poll(mate, room.id(), 0L, null).path("items").get(0);
        JsonNode forOwner = poll(owner, room.id(), 0L, null).path("items").get(0);

        assertThat(count(forMate, "check")).isEqualTo(1);
        assertThat(count(forOwner, "check")).isEqualTo(1);
        assertThat(forMate.path("reactions").get(0).path("mine").asBoolean()).isTrue();
        assertThat(forOwner.path("reactions").get(0).path("mine").asBoolean())
                .as("hiddenByBlock 과 같은 종류의 값이다 — 캐시할 수 없다")
                .isFalse();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private record Room(long id, String title) { }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("chat452-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /** 방 하나와 멤버들 — 입장은 초대코드 경로 그대로다(멤버십 기본값을 테스트가 다시 정하지 않는다). */
    private Room roomWith(Account owner, Account... others) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        String title = "방-%d-%d".formatted(System.nanoTime(), serial);
        ChatRoomView room = chatRooms.openRoom(
                "CHAT452_TEST", String.valueOf(serial), title, "테스트", owner.id());
        for (Account other : others) {
            String code = chatRooms.issueInvite(room.id(), owner.id()).code();
            chatRooms.joinByInviteCode(code, other.id());
        }
        return new Room(room.id(), title);
    }

    private ResultActions send(Account account, long roomId, String text) throws Exception {
        return mockMvc.perform(post("/api/chat/rooms/{roomId}/messages", roomId)
                        .header("Authorization", "Bearer " + account.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"body\":\"%s\"}".formatted(text)))
                .andExpect(status().isCreated());
    }

    private ResultActions react(Account account, long messageId, String kind) throws Exception {
        return mockMvc.perform(post("/api/chat/messages/{messageId}/reactions/{kind}", messageId, kind)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions unreact(Account account, long messageId, String kind) throws Exception {
        return mockMvc.perform(delete("/api/chat/messages/{messageId}/reactions/{kind}", messageId, kind)
                .header("Authorization", "Bearer " + account.token()));
    }

    private MockHttpServletRequestBuilder pollRequest(Account account, long roomId,
                                                      Long afterSeq, Long afterChangeSeq) {
        MockHttpServletRequestBuilder request = get("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + account.token());
        if (afterSeq != null) {
            request = request.param("afterSeq", String.valueOf(afterSeq));
        }
        if (afterChangeSeq != null) {
            request = request.param("afterChangeSeq", String.valueOf(afterChangeSeq));
        }
        return request;
    }

    private JsonNode poll(Account account, long roomId, Long afterSeq, Long afterChangeSeq)
            throws Exception {
        return body(mockMvc.perform(pollRequest(account, roomId, afterSeq, afterChangeSeq))
                .andExpect(status().isOk()));
    }

    private JsonNode roomInList(Account account, long roomId) throws Exception {
        JsonNode rooms = body(mockMvc.perform(get("/api/chat/rooms")
                .header("Authorization", "Bearer " + account.token())).andExpect(status().isOk()));
        for (JsonNode room : rooms) {
            if (room.path("id").asLong() == roomId) {
                return room;
            }
        }
        throw new AssertionError("방 목록에 " + roomId + " 이 없다: " + rooms);
    }

    private static long idOf(ResultActions sent) throws Exception {
        return body(sent).path("id").asLong();
    }

    /** 이 메시지(또는 반응 응답)의 그 종류 집계. 없으면 0. */
    private static int count(JsonNode node, String kind) {
        for (JsonNode reaction : node.path("reactions")) {
            if (kind.equals(reaction.path("kind").asText())) {
                return reaction.path("count").asInt();
            }
        }
        return 0;
    }

    private static java.util.List<String> kinds(JsonNode node) {
        java.util.List<String> out = new java.util.ArrayList<>();
        node.path("reactions").forEach(reaction -> out.add(reaction.path("kind").asText()));
        return out;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(
                actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }
}
