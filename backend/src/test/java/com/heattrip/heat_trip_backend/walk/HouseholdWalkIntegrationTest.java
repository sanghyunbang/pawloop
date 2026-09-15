package com.heattrip.heat_trip_backend.walk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
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
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.StreamSupport;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 산책이 집 것이 된다 — 이슈 #563 조각 3.
 *
 * <h2>무엇을 보증하나</h2>
 *
 * <p>이 앱의 목적은 <b>업무 분담과 누락 방지</b>다(#76). 그런데 {@code walk} 표에 사람
 * 컬럼이 없어서 산책의 주인이 <b>아이의 주인</b>이었다.
 *
 * <pre>select w from Walk w join fetch w.dog d where d.user.id = :userId</pre>
 *
 * <p>그래서 아빠가 엄마 아이 보리를 산책시키면 (1) 저장 자체가 거절되고, (2) 소유 검사만
 * 풀면 그 기록이 <b>엄마 목록에만</b> 갔다. 아빠는 방금 걸은 경로를 못 봤다.
 *
 * <p>여기서 재는 것은 넷이다 — <b>저장되는가 · 둘 다 보는가 · 누가 걸었는지 남는가 ·
 * 남의 기록을 못 고치는가.</b> 마지막이 중요하다: 보기는 집 전체로 넓히면서 고치기까지
 * 넓히면, 분담을 보이게 하려던 화면이 서로의 기록을 지우는 자리가 된다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class HouseholdWalkIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private ChatRoomService chatRooms;

    @Test
    @DisplayName("아빠가 엄마 아이 보리를 산책시키면 저장되고, 둘 다 그 기록을 본다")
    void anyoneInTheHouseholdCanWalkAndEveryoneSeesIt() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        family(mom, dad);

        JsonNode saved = body(walk(dad, bori).andExpect(status().isCreated()));

        assertThat(saved.path("walkedBy").path("nickname").asText())
                .as("분담이 보이려면 '누가 걸었나' 가 기록에 남아야 한다")
                .isEqualTo("아빠");
        assertThat(ids(list(dad))).as("아빠는 방금 걸은 경로를 자기 기록에서 봐야 한다")
                .containsExactly(saved.path("id").asLong());
        assertThat(ids(list(mom))).as("엄마도 본다 — 안 보이면 '아직 안 나갔나' 싶어 한 번 더 나간다")
                .containsExactly(saved.path("id").asLong());
    }

    @Test
    @DisplayName("상세와 통계도 집 기준이다 — 주간 목표는 아이의 것이지 사람의 것이 아니다")
    void detailAndStatsAreHouseholdScoped() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        family(mom, dad);

        long walkId = body(walk(dad, bori).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(get("/api/walks/{walkId}", walkId)
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isOk());

        JsonNode stats = body(mockMvc.perform(get("/api/walks/stats/weekly")
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isOk()));
        assertThat(stats.path("walkCount").asInt())
                .as("소형견 150분/주는 보리의 목표지 엄마의 목표가 아니다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("남의 집 아이로는 못 걷는다 — 404")
    void aDogFromAnotherHouseIsNotFound() throws Exception {
        Account mom = account("엄마");
        Account stranger = account("남");
        long theirDog = dog(stranger, "남의개");
        family(mom);

        walk(mom, theirDog).andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("가족이 없는 1인은 지금과 똑같다 — 자기 아이만 걷고 자기 기록만 본다")
    void aSoloUserSeesExactlyWhatTheyDidBefore() throws Exception {
        Account solo = account("혼자");
        Account other = account("남");
        long myDog = dog(solo, "콩이");
        long theirDog = dog(other, "남의개");

        long walkId = body(walk(solo, myDog).andExpect(status().isCreated())).path("id").asLong();

        assertThat(ids(list(solo))).containsExactly(walkId);
        walk(solo, theirDog).andExpect(status().isNotFound());
        assertThat(ids(list(other))).as("남의 기록이 새어 나가면 안 된다").isEmpty();
    }

    @Test
    @DisplayName("보기는 집 전체지만 고치기·지우기는 걸은 사람이거나 아이 주인만이다")
    void seeingIsSharedButEditingIsNot() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        Account sister = account("누나");
        long bori = dog(mom, "보리");
        family(mom, dad, sister);

        long walkId = body(walk(dad, bori).andExpect(status().isCreated())).path("id").asLong();

        // 누나는 본다.
        assertThat(ids(list(sister))).containsExactly(walkId);
        // 그런데 못 고치고 못 지운다 — 걸은 사람도 아이 주인도 아니다.
        memo(sister, walkId, "누나가 덮어쓴 회고").andExpect(status().isNotFound());
        mockMvc.perform(delete("/api/walks/{walkId}", walkId)
                        .header("Authorization", "Bearer " + sister.token()))
                .andExpect(status().isNotFound());

        // 걸은 사람은 고칠 수 있다.
        memo(dad, walkId, "비 와서 짧게").andExpect(status().isOk());
        // 아이 주인도 고칠 수 있다 — 걸은 사람이 탈퇴하면 아무도 못 고치는 행이 생기면 안 된다.
        memo(mom, walkId, "보리가 신났다").andExpect(status().isOk());
    }

    @Test
    @DisplayName("가족을 나가면 그 순간 그 집 산책이 안 보인다")
    void leavingTheHouseholdHidesItsWalks() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        long roomId = family(mom, dad);

        long walkId = body(walk(dad, bori).andExpect(status().isCreated())).path("id").asLong();
        assertThat(ids(list(dad))).containsExactly(walkId);

        chatRooms.leaveRoom(roomId, dad.id());

        assertThat(ids(list(dad)))
                .as("보리는 이제 아빠 집 아이가 아니다. 기록은 사라지지 않고 엄마에게 남는다")
                .isEmpty();
        assertThat(ids(list(mom))).containsExactly(walkId);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("household-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
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

    /** 방장과 나머지 식구로 가족 하나. 방 id 를 돌려준다. */
    private long family(Account owner, Account... others) throws Exception {
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
        return roomId;
    }

    private ResultActions walk(Account actor, long dogId) throws Exception {
        return mockMvc.perform(post("/api/walks")
                .header("Authorization", "Bearer " + actor.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content("""
                        {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":1200,"durationS":900}
                        """.formatted(dogId, UUID.randomUUID(), Instant.now().toString())));
    }

    private ResultActions memo(Account actor, long walkId, String text) throws Exception {
        return mockMvc.perform(put("/api/walks/{walkId}/memo", walkId)
                .header("Authorization", "Bearer " + actor.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"memo\":\"%s\"}".formatted(text)));
    }

    private JsonNode list(Account actor) throws Exception {
        return body(mockMvc.perform(get("/api/walks")
                        .header("Authorization", "Bearer " + actor.token()))
                .andExpect(status().isOk()));
    }

    private List<Long> ids(JsonNode page) {
        return StreamSupport.stream(page.path("items").spliterator(), false)
                .map(node -> node.path("id").asLong())
                .toList();
    }

    private JsonNode body(ResultActions actions) throws Exception {
        MockHttpServletResponse response = actions.andReturn().getResponse();
        return objectMapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }
}
