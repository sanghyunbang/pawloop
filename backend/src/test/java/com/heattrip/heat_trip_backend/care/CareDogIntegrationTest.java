package com.heattrip.heat_trip_backend.care;

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
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.StreamSupport;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 케어 기록에 아이가 붙는다 — 이슈 #563 조각 2.
 *
 * <h2>무엇을 보증하나</h2>
 *
 * <p>이 기능의 목적은 <b>업무 분담과 누락 방지</b>다(#76). "해당 동물을 누르면 누가
 * 산책시켰고 누가 물 줬는지" 가 보여야 하는데, 그러려면 기록에 아이가 붙어야 한다.
 * 그 전까지 {@code care_log.dog_id} 는 컬럼과 FK 만 있고 값이 항상 {@code null} 이었다.
 *
 * <p>여기서 재는 것은 셋이다.
 * <ol>
 *   <li><b>남이 등록한 아이에게도 기록할 수 있다.</b> 엄마가 등록한 보리에게 아빠가 물을
 *       주는 것이 이 기능의 목적이다 — 막으면 기능이 없는 것과 같다.</li>
 *   <li><b>아이로 거르면 그 아이 것만 나온다.</b> 두 마리 집에서 보리 카드가 누리 밥까지
 *       세면 "오늘 무엇이 남았나" 에 거짓으로 답한다.</li>
 *   <li><b>아이 없는 옛 기록은 계속 보인다.</b> 빼면 어제 준 밥이 사라지고, 사라지면
 *       "아직" 으로 읽혀 한 번 더 준다.</li>
 * </ol>
 */
@SpringBootTest
@AutoConfigureMockMvc
class CareDogIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;

    @Test
    @DisplayName("아빠가 엄마 아이 보리에게 물을 주면 보리 기록으로 남는다 — 이 기능의 목적이다")
    void anyoneInTheFamilyCanCareForAnyDogOfTheHouse() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        Family family = family(mom, dad);

        JsonNode saved = body(record(dad, family.groupId(), "water", bori)
                .andExpect(status().isCreated()));

        assertThat(saved.path("dogId").asLong())
                .as("남이 등록한 아이라고 막으면 이 기능은 없는 것과 같다")
                .isEqualTo(bori);
        assertThat(saved.path("doneBy").path("nickname").asText())
                .as("분담이 보이려면 '누가' 가 남아야 한다")
                .isEqualTo("아빠");
    }

    @Test
    @DisplayName("아이로 거르면 그 아이 것만 온다 — 보리 카드가 누리 밥을 세면 안 된다")
    void filteringByDogSeparatesTheDogs() throws Exception {
        Account mom = account("엄마");
        long bori = dog(mom, "보리");
        long nuri = dog(mom, "누리");
        Family family = family(mom);

        record(mom, family.groupId(), "meal", bori).andExpect(status().isCreated());
        record(mom, family.groupId(), "meal", nuri).andExpect(status().isCreated());
        record(mom, family.groupId(), "water", nuri).andExpect(status().isCreated());

        assertThat(types(logs(mom, family.groupId(), bori))).containsExactly("meal");
        assertThat(types(logs(mom, family.groupId(), nuri))).containsExactly("meal", "water");
        assertThat(types(logs(mom, family.groupId(), null)))
                .as("아이를 안 물으면 전부 — 가족 화면이 그렇게 본다")
                .containsExactly("meal", "meal", "water");
    }

    @Test
    @DisplayName("아이 없는 옛 기록은 어느 아이를 골라도 계속 보인다 — 빼면 어제 준 밥이 사라진다")
    void logsWithoutADogStayVisibleUnderEveryDog() throws Exception {
        Account mom = account("엄마");
        long bori = dog(mom, "보리");
        long nuri = dog(mom, "누리");
        Family family = family(mom);

        // 옛 앱이 보내던 모양 — dogId 가 아예 없다.
        record(mom, family.groupId(), "meal", null).andExpect(status().isCreated());
        record(mom, family.groupId(), "water", bori).andExpect(status().isCreated());

        assertThat(types(logs(mom, family.groupId(), bori)))
                .as("""
                        아이 없는 행을 빼면 화면이 "아직" 이라고 말하고, 그걸 본 사람이 한 번 더 \
                        준다. 이 표가 막으려는 것이 정확히 그 이중 급여다(#76).""")
                .containsExactly("meal", "water");
        assertThat(types(logs(mom, family.groupId(), nuri)))
                .as("어느 아이 것인지 모르는 값이라 어느 쪽으로 눕혀도 지어내는 것이 된다")
                .containsExactly("meal");
    }

    @Test
    @DisplayName("dogId 를 안 보내도 기록된다 — 아이가 없는 집도, 옛 앱도 그대로 돈다")
    void dogIdIsOptional() throws Exception {
        Account mom = account("엄마");
        Family family = family(mom);

        JsonNode saved = body(record(mom, family.groupId(), "water", null)
                .andExpect(status().isCreated()));

        assertThat(saved.path("dogId").isNull())
                .as("필수로 두면 아이를 한 마리도 등록 안 한 집은 아무것도 못 적는다")
                .isTrue();
    }

    @Test
    @DisplayName("우리 집 아이가 아니면 400 — 남의 집 아이에 기록을 붙일 수 없다")
    void aDogFromAnotherHouseIsRejected() throws Exception {
        Account mom = account("엄마");
        Account stranger = account("남");
        long theirDog = dog(stranger, "남의개");
        Family family = family(mom);

        record(mom, family.groupId(), "meal", theirDog).andExpect(status().isBadRequest());
        record(mom, family.groupId(), "meal", 9_999_999L).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("가족을 나간 사람의 아이에는 더 못 붙인다 — 그 순간 집 아이가 아니다")
    void aDogThatLeftTheHouseIsRejected() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long mungchi = dog(dad, "뭉치");
        Family family = family(mom, dad);

        record(mom, family.groupId(), "meal", mungchi).andExpect(status().isCreated());
        chatRooms.leaveRoom(family.roomId(), dad.id());

        record(mom, family.groupId(), "meal", mungchi)
                .andExpect(status().isBadRequest());
        assertThat(logs(mom, family.groupId(), null))
                .as("이미 쌓인 기록은 집에 남는다 — 지우는 것이 아니라 더 못 붙이는 것이다")
                .hasSize(1);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    @Autowired private com.heattrip.heat_trip_backend.chat.ChatRoomService chatRooms;

    private record Account(long id, String token) { }

    private record Family(long groupId, long roomId) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = consented(users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("caredog-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private long dog(Account owner, String name) throws Exception {
        return body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s","breed":"푸들","size":"small","birth":"2024-09-01","neutered":false}
                                """.formatted(name)))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    /** 방장과 나머지 식구로 가족 하나. */
    private Family family(Account owner, Account... others) throws Exception {
        JsonNode group = body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"보리네\"}"))
                .andExpect(status().isCreated()));
        long roomId = group.path("roomId").asLong();
        for (Account other : others) {
            String code = body(mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                            .header("Authorization", "Bearer " + owner.token()))
                    .andExpect(status().isCreated())).path("code").asText();
            mockMvc.perform(post("/api/chat/invites/{code}/join", code)
                            .header("Authorization", "Bearer " + other.token()))
                    .andExpect(status().isOk());
        }
        return new Family(group.path("id").asLong(), roomId);
    }

    private ResultActions record(Account actor, long groupId, String type, Long dogId)
            throws Exception {
        String content = dogId == null
                ? "{\"type\":\"%s\"}".formatted(type)
                : "{\"type\":\"%s\",\"dogId\":%d}".formatted(type, dogId);
        return mockMvc.perform(post("/api/groups/{groupId}/care-logs", groupId)
                .header("Authorization", "Bearer " + actor.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(content));
    }

    private JsonNode logs(Account actor, long groupId, Long dogId) throws Exception {
        var request = get("/api/groups/{groupId}/care-logs", groupId)
                .header("Authorization", "Bearer " + actor.token());
        if (dogId != null) {
            request = request.param("dogId", String.valueOf(dogId));
        }
        return body(mockMvc.perform(request).andExpect(status().isOk()));
    }

    private List<String> types(JsonNode array) {
        return StreamSupport.stream(array.spliterator(), false)
                .map(node -> node.path("type").asText())
                .toList();
    }

    private JsonNode body(ResultActions actions) throws Exception {
        MockHttpServletResponse response = actions.andReturn().getResponse();
        return objectMapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }
}
