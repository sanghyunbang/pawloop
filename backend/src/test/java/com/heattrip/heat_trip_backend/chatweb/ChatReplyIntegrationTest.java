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
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 답장(인용) — 이슈 #452. 원문의 내용은 저장하지 않고 응답 때마다 읽는다: 원문이 지워지면 미리보기가
 * "삭제된 메시지" 가 되고, 원문을 보낸 사람의 이름은 지금 이름이다. 다른 방의 메시지에는 답장할 수 없다.
 *
 * <p>스프링 컨텍스트 설정은 {@code ChatPhotoMessageIntegrationTest} 와 달리 목이 없어 기본 컨텍스트를
 * 다시 쓴다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
class ChatReplyIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private ChatRoomService chatRooms;

    @Test
    @DisplayName("답장을 보내면 응답 · 장 · 델타에 원문 미리보기(보낸 사람의 지금 이름 · 첫 줄)가 온다 — 원문에는 없다")
    void aReplyCarriesTheOriginalPreview() throws Exception {
        Account dad = account("보리아빠");
        Account mom = account("보리엄마");
        Room room = roomWith(dad, mom);
        long original = body(send(mom, room.id(), "{\"body\":\"저녁 산책\\n갈까요?\",\"clientMsgId\":\"o-1\"}")
                .andExpect(status().isCreated())).path("id").asLong();

        JsonNode reply = body(send(dad, room.id(),
                "{\"body\":\"좋아요 7시에\",\"clientMsgId\":\"r-1\",\"replyToId\":" + original + "}")
                .andExpect(status().isCreated()));

        JsonNode replyTo = reply.path("replyTo");
        assertThat(replyTo.path("id").asLong()).isEqualTo(original);
        assertThat(replyTo.path("senderName").asText()).isEqualTo("보리엄마");
        assertThat(replyTo.path("preview").asText()).as("줄바꿈은 한 칸으로").isEqualTo("저녁 산책 갈까요?");
        assertThat(replyTo.path("deleted").asBoolean()).isFalse();

        JsonNode page = messages(dad, room.id(), null);
        assertThat(page.path("items").get(0).path("replyTo").isNull()).as("원문은 답장이 아니다").isTrue();
        assertThat(page.path("items").get(1).path("replyTo").path("preview").asText()).as("장(page)에도")
                .isEqualTo("저녁 산책 갈까요?");
        JsonNode delta = messages(mom, room.id(), 1L);
        assertThat(delta.path("items").get(0).path("replyTo").path("senderName").asText()).as("델타(afterSeq)에도")
                .isEqualTo("보리엄마");
    }

    @Test
    @DisplayName("원문이 지워지면 미리보기는 '삭제된 메시지' 이고 답장은 그대로 남는다")
    void aDeletedOriginalShowsAsDeleted() throws Exception {
        Account dad = account("지우는아빠");
        Room room = roomWith(dad);
        long original = body(send(dad, room.id(), "{\"body\":\"지울 말\",\"clientMsgId\":\"o-2\"}")
                .andExpect(status().isCreated())).path("id").asLong();
        send(dad, room.id(), "{\"body\":\"답\",\"clientMsgId\":\"r-2\",\"replyToId\":" + original + "}")
                .andExpect(status().isCreated());

        mockMvc.perform(delete("/api/chat/messages/" + original)
                .header("Authorization", "Bearer " + dad.token())).andExpect(status().isNoContent());

        JsonNode last = messages(dad, room.id(), null).path("items").get(1);
        assertThat(last.path("body").asText()).isEqualTo("답");
        assertThat(last.path("replyTo").path("deleted").asBoolean()).isTrue();
        assertThat(last.path("replyTo").path("preview").asText()).isEqualTo("삭제된 메시지");
    }

    @Test
    @DisplayName("다른 방의 메시지에는 답장할 수 없다 — 400 이고 번호도 안 태운다")
    void rejectsAReplyAcrossRooms() throws Exception {
        Account a = account("에이");
        Account b = account("비");
        Room roomA = roomWith(a);
        Room roomB = roomWith(b);
        long inB = body(send(b, roomB.id(), "{\"body\":\"비의 말\",\"clientMsgId\":\"o-3\"}")
                .andExpect(status().isCreated())).path("id").asLong();

        send(a, roomA.id(), "{\"body\":\"엿듣기\",\"clientMsgId\":\"r-3\",\"replyToId\":" + inB + "}")
                .andExpect(status().isBadRequest());
        send(a, roomA.id(), "{\"body\":\"없는 말에\",\"clientMsgId\":\"r-4\",\"replyToId\":999999}")
                .andExpect(status().isBadRequest());

        assertThat(body(send(a, roomA.id(), "{\"body\":\"그냥 말\",\"clientMsgId\":\"n-3\"}")
                .andExpect(status().isCreated())).path("roomSeq").asLong())
                .as("거절된 답장이 번호를 태우지 않았다").isEqualTo(1);
    }

    @Test
    @DisplayName("긴 원문은 80자에서 잘린다 — 이모지도 한 자다")
    void previewIsCut() throws Exception {
        Account dad = account("긴글");
        Room room = roomWith(dad);
        String longText = "🐶".repeat(100);
        long original = body(send(dad, room.id(), "{\"body\":\"" + longText + "\",\"clientMsgId\":\"o-5\"}")
                .andExpect(status().isCreated())).path("id").asLong();

        JsonNode reply = body(send(dad, room.id(), "{\"body\":\"응\",\"clientMsgId\":\"r-5\",\"replyToId\":" + original + "}")
                .andExpect(status().isCreated()));

        String preview = reply.path("replyTo").path("preview").asText();
        assertThat(preview).endsWith("…");
        assertThat(preview.codePointCount(0, preview.length())).isEqualTo(81);
        assertThat(preview).as("보조평면 문자를 반으로 자르지 않는다").doesNotContain("�");
    }

    @Test
    @DisplayName("같은 clientMsgId 로 다시 보내면 200 이고 미리보기도 그대로 온다")
    void aResendKeepsThePreview() throws Exception {
        Account dad = account("재전송");
        Room room = roomWith(dad);
        long original = body(send(dad, room.id(), "{\"body\":\"원문\",\"clientMsgId\":\"o-6\"}")
                .andExpect(status().isCreated())).path("id").asLong();
        String json = "{\"body\":\"답\",\"clientMsgId\":\"r-6\",\"replyToId\":" + original + "}";
        send(dad, room.id(), json).andExpect(status().isCreated());

        JsonNode again = body(send(dad, room.id(), json).andExpect(status().isOk()));

        assertThat(again.path("replyTo").path("preview").asText()).isEqualTo("원문");
    }

    // ─────────────────────────── 도우미 ───────────────────────────

    private ResultActions send(Account account, long roomId, String json) throws Exception {
        return mockMvc.perform(post("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private JsonNode messages(Account account, long roomId, Long afterSeq) throws Exception {
        MockHttpServletRequestBuilder request = get("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + account.token());
        if (afterSeq != null) {
            request = request.param("afterSeq", String.valueOf(afterSeq));
        }
        return body(mockMvc.perform(request).andExpect(status().isOk()));
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    private record Account(long id, String token) { }

    private record Room(long id) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("reply452-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /** 방 하나와 멤버들 — 입장은 초대코드 경로(#75) 그대로, 멤버십 행을 손으로 만들지 않는다. */
    private Room roomWith(Account owner, Account... others) {
        long serial = SEQUENCE.incrementAndGet();
        ChatRoomView room = chatRooms.openRoom(
                "REPLY452_TEST", String.valueOf(serial) + "-" + UUID.randomUUID(), "방-%d".formatted(serial), "테스트", owner.id());
        for (Account other : others) {
            String code = chatRooms.issueInvite(room.id(), owner.id()).code();
            chatRooms.joinByInviteCode(code, other.id());
        }
        return new Room(room.id());
    }
}
