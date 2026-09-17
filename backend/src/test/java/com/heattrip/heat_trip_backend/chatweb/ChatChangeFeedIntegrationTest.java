package com.heattrip.heat_trip_backend.chatweb;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
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
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 변경 피드 — ADR-0023(#500). 이미 보낸 말이 바뀌면 델타가 그것을 {@code changed} 로 흘려보낸다.
 *
 * <p>지금 그 변화는 <b>삭제</b> 하나다(#197). 이 테스트가 재는 것은 "남이 지운 말이 내 폴링에 따라오는가" 이고,
 * 그것이 안 되던 것이 이 기능 이전의 상태다 — 앱이 방을 다시 열기 전까지 지워진 말을 그대로 봤다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class ChatChangeFeedIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private ChatRoomService chatRooms;

    @Test
    @DisplayName("남이 지운 말이 내 폴링에 changed 로 따라온다 — items 는 비어 있고 lastChangeSeq 가 오른다")
    void aDeleteReachesTheOtherMember() throws Exception {
        Account dad = account("지우는사람");
        Account mom = account("보는사람");
        Room room = roomWith(dad, mom);
        long target = body(send(dad, room.id(), "{\"body\":\"지울 말\",\"clientMsgId\":\"c-1\"}")).path("id").asLong();
        send(dad, room.id(), "{\"body\":\"남을 말\",\"clientMsgId\":\"c-2\"}");

        JsonNode caughtUp = delta(mom, room.id(), 0L, 0L);
        long lastSeq = caughtUp.path("lastSeq").asLong();
        assertThat(caughtUp.path("changed")).as("아직 바뀐 것이 없다").isEmpty();
        assertThat(caughtUp.path("lastChangeSeq").asLong()).isZero();

        mockMvc.perform(delete("/api/chat/messages/{id}", target)
                .header("Authorization", "Bearer " + dad.token())).andExpect(status().isNoContent());

        JsonNode after = delta(mom, room.id(), lastSeq, 0L);

        assertThat(after.path("items")).as("새 말은 없다").isEmpty();
        assertThat(after.path("changed")).singleElement().satisfies(changed -> {
            assertThat(changed.path("id").asLong()).isEqualTo(target);
            assertThat(changed.path("deletedAt").isNull()).as("톰스톤이 왔다").isFalse();
            assertThat(changed.path("body").asText()).isEmpty();
        });
        assertThat(after.path("lastChangeSeq").asLong()).isEqualTo(1);
    }

    @Test
    @DisplayName("따라잡은 커서로 다시 물으면 changed 는 비어 있다 — 같은 변화를 두 번 주지 않는다")
    void aCaughtUpCursorGetsNothing() throws Exception {
        Account dad = account("따라잡기");
        Room room = roomWith(dad);
        long target = body(send(dad, room.id(), "{\"body\":\"지울 말\",\"clientMsgId\":\"c-3\"}")).path("id").asLong();
        mockMvc.perform(delete("/api/chat/messages/{id}", target)
                .header("Authorization", "Bearer " + dad.token())).andExpect(status().isNoContent());

        JsonNode first = delta(dad, room.id(), 1L, 0L);
        assertThat(first.path("changed")).hasSize(1);

        JsonNode second = delta(dad, room.id(), 1L, first.path("lastChangeSeq").asLong());

        assertThat(second.path("changed")).isEmpty();
    }

    @Test
    @DisplayName("바뀐 말이 있으면 304 가 아니다 — ETag 에 변경 번호가 들어 있다")
    void anEtagFromBeforeTheChangeDoesNotGive304() throws Exception {
        Account dad = account("이태그");
        Room room = roomWith(dad);
        long target = body(send(dad, room.id(), "{\"body\":\"지울 말\",\"clientMsgId\":\"c-4\"}")).path("id").asLong();

        MvcResult fresh = mockMvc.perform(pollRequest(dad, room.id(), 1L, 0L))
                .andExpect(status().isOk()).andReturn();
        String etag = fresh.getResponse().getHeader(HttpHeaders.ETAG);
        assertThat(etag).as("ETag 는 방 · 마지막 번호 · 변경 번호 셋이다").isEqualTo("\"%d:1:0\"".formatted(room.id()));

        // 아무것도 안 바뀐 사이에는 304 다.
        mockMvc.perform(pollRequest(dad, room.id(), 1L, 0L).header(HttpHeaders.IF_NONE_MATCH, etag))
                .andExpect(status().isNotModified());

        mockMvc.perform(delete("/api/chat/messages/{id}", target)
                .header("Authorization", "Bearer " + dad.token())).andExpect(status().isNoContent());

        MvcResult afterDelete = mockMvc.perform(
                        pollRequest(dad, room.id(), 1L, 0L).header(HttpHeaders.IF_NONE_MATCH, etag))
                .andExpect(status().isOk()).andReturn();

        assertThat(afterDelete.getResponse().getHeader(HttpHeaders.ETAG))
                .isEqualTo("\"%d:1:1\"".formatted(room.id()));
        assertThat(MAPPER.readTree(afterDelete.getResponse().getContentAsString(StandardCharsets.UTF_8))
                .path("changed")).hasSize(1);
    }

    @Test
    @DisplayName("커서를 안 주면 changed 는 빈 목록이다 — 첫 진입은 그 장이 이미 최신이다")
    void aFirstEntryCarriesNoChanges() throws Exception {
        Account dad = account("첫진입");
        Room room = roomWith(dad);
        long target = body(send(dad, room.id(), "{\"body\":\"지울 말\",\"clientMsgId\":\"c-5\"}")).path("id").asLong();
        mockMvc.perform(delete("/api/chat/messages/{id}", target)
                .header("Authorization", "Bearer " + dad.token())).andExpect(status().isNoContent());

        JsonNode page = body(mockMvc.perform(get("/api/chat/rooms/{id}/messages", room.id())
                .header("Authorization", "Bearer " + dad.token())).andExpect(status().isOk()));

        assertThat(page.path("changed")).isEmpty();
        assertThat(page.path("lastChangeSeq").asLong()).as("커서를 갱신할 값은 늘 준다").isEqualTo(1);
        assertThat(page.path("items")).singleElement()
                .satisfies(item -> assertThat(item.path("deletedAt").isNull()).isFalse());
    }

    @Test
    @DisplayName("두 번 지워도 변경 번호는 한 번만 오른다")
    void deletingTwiceBumpsOnce() throws Exception {
        Account dad = account("두번삭제");
        Room room = roomWith(dad);
        long target = body(send(dad, room.id(), "{\"body\":\"지울 말\",\"clientMsgId\":\"c-6\"}")).path("id").asLong();

        for (int i = 0; i < 2; i++) {
            mockMvc.perform(delete("/api/chat/messages/{id}", target)
                    .header("Authorization", "Bearer " + dad.token())).andExpect(status().isNoContent());
        }

        assertThat(delta(dad, room.id(), 1L, 0L).path("lastChangeSeq").asLong()).isEqualTo(1);
    }

    @Test
    @DisplayName("남의 삭제 시도(403)는 변경 번호를 올리지 않는다")
    void aForbiddenDeleteChangesNothing() throws Exception {
        Account dad = account("주인");
        Account other = account("남");
        Room room = roomWith(dad, other);
        long target = body(send(dad, room.id(), "{\"body\":\"내 말\",\"clientMsgId\":\"c-7\"}")).path("id").asLong();

        mockMvc.perform(delete("/api/chat/messages/{id}", target)
                .header("Authorization", "Bearer " + other.token())).andExpect(status().isForbidden());

        assertThat(delta(dad, room.id(), 1L, 0L).path("lastChangeSeq").asLong()).isZero();
    }

    // ─────────────────────────── 도우미 ───────────────────────────

    private MockHttpServletRequestBuilder pollRequest(Account me, long roomId, long afterSeq, long afterChangeSeq) {
        return get("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + me.token())
                .param("afterSeq", String.valueOf(afterSeq))
                .param("afterChangeSeq", String.valueOf(afterChangeSeq));
    }

    private JsonNode delta(Account me, long roomId, long afterSeq, long afterChangeSeq) throws Exception {
        return body(mockMvc.perform(pollRequest(me, roomId, afterSeq, afterChangeSeq)).andExpect(status().isOk()));
    }

    private ResultActions send(Account account, long roomId, String json) throws Exception {
        return mockMvc.perform(post("/api/chat/rooms/{roomId}/messages", roomId)
                        .header("Authorization", "Bearer " + account.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isCreated());
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    private record Account(long id, String token) { }

    private record Room(long id) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("changefeed-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /** 방 하나와 멤버들 — 입장은 초대코드 경로(#75) 그대로. */
    private Room roomWith(Account owner, Account... others) {
        long serial = SEQUENCE.incrementAndGet();
        ChatRoomView room = chatRooms.openRoom(
                "CHANGEFEED_TEST", serial + "-" + UUID.randomUUID(), "방-%d".formatted(serial), "테스트", owner.id());
        for (Account other : others) {
            String code = chatRooms.issueInvite(room.id(), owner.id()).code();
            chatRooms.joinByInviteCode(code, other.id());
        }
        return new Room(room.id());
    }
}
