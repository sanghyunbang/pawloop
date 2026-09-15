package com.heattrip.heat_trip_backend.dog;

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
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static java.util.Map.entry;
import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 우리 집 아이 목록 — 이슈 #563.
 *
 * <h2>무엇을 보증하나</h2>
 *
 * <p>이 앱의 목적은 <b>업무 분담과 누락 방지</b>다(#76). 그런데 아이가 사람 것이라, 엄마가
 * 보리를 등록하고 아빠가 가족에 들어오면 <b>아빠 홈은 "아직 등록된 아이가 없어요"</b> 였다.
 * 아빠가 보리를 또 등록하면 같은 아이가 두 마리가 되고 케어 기록이 둘로 갈린다.
 *
 * <p>그래서 이 파일이 재는 것은 한 문장이다 — <b>"가족에 들어오면 그 순간 그 집 아이가 전부
 * 보이고, 나가면 그 순간 빠진다."</b> 표를 안 바꾸고 식구 목록에서 파생하기 때문에, 승계
 * 코드가 없어도 그렇게 되는지를 HTTP 로 확인한다.
 *
 * <p>함께 잠그는 것은 <b>공유되는 것이 돌봄이지 소유가 아니라는 것</b>이다 — 남이 등록한
 * 아이의 상세 · 수정 · 삭제는 여전히 404 다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class FamilyDogsIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private ChatRoomService chatRooms;

    @Test
    @DisplayName("가족에 들어오면 그 순간 그 집 아이가 보인다 — 또 등록할 필요가 없다")
    void joiningAFamilyShowsItsDogs() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        JsonNode group = createGroup(mom, "보리네");
        join(dad, invite(mom, group.path("roomId").asLong()));

        JsonNode dogs = body(familyDogs(dad, group.path("id").asLong()).andExpect(status().isOk()));

        assertThat(names(dogs))
                .as("""
                        아빠는 보리를 등록한 적이 없다. 이 목록이 비어 있던 동안 아빠 홈은 \
                        "아직 등록된 아이가 없어요" 였고, 그래서 아빠가 보리를 또 등록했다.""")
                .containsExactly("보리");
        assertThat(dogs.get(0).path("id").asLong()).isEqualTo(bori);
    }

    @Test
    @DisplayName("내 아이와 남의 아이가 한 목록에 온다 — 등록한 사람별로 모여서")
    void bothMembersDogsComeTogether() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        dog(mom, "보리");
        dog(mom, "누리");
        dog(dad, "뭉치");
        JsonNode group = createGroup(mom, "보리네");
        join(dad, invite(mom, group.path("roomId").asLong()));

        JsonNode dogs = body(familyDogs(dad, group.path("id").asLong()).andExpect(status().isOk()));

        assertThat(names(dogs))
                .as("한 사람 것이 흩어지면 홈 스위처에서 누구 아이인지 매번 이름을 봐야 한다")
                .containsExactly("보리", "누리", "뭉치");
    }

    @Test
    @DisplayName("가족을 나가면 그 순간 빠진다 — 옮기는 코드도 되돌리는 코드도 없다")
    void leavingTakesTheDogsAway() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        dog(mom, "보리");
        dog(dad, "뭉치");
        JsonNode group = createGroup(mom, "보리네");
        long roomId = group.path("roomId").asLong();
        long groupId = group.path("id").asLong();
        join(dad, invite(mom, roomId));

        assertThat(names(body(familyDogs(mom, groupId)))).containsExactly("보리", "뭉치");

        // 방 나가기의 HTTP 경로는 계약에 선언만 돼 있고 아직 안 열렸다(ChatRoomService javadoc).
        // 그래서 공개 표면을 직접 부른다 — 재려는 것은 "나가면 빠지는가" 이지 그 경로가 아니다.
        chatRooms.leaveRoom(roomId, dad.id());

        assertThat(names(body(familyDogs(mom, groupId))))
                .as("식구 목록에서 파생하므로 아무 코드도 안 돌리고 빠진다")
                .containsExactly("보리");
    }

    @Test
    @DisplayName("공유되는 것은 돌봄이지 소유가 아니다 — 남의 아이 상세 · 수정 · 삭제는 그대로 404")
    void sharingCareDoesNotShareOwnership() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        JsonNode group = createGroup(mom, "보리네");
        join(dad, invite(mom, group.path("roomId").asLong()));

        // 목록에는 보인다.
        assertThat(names(body(familyDogs(dad, group.path("id").asLong())))).contains("보리");

        mockMvc.perform(get("/api/dogs/{dogId}", bori)
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNotFound());
        mockMvc.perform(delete("/api/dogs/{dogId}", bori)
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("남이 등록한 아이는 mine=false 다 — 앱이 이 값으로 '고칠 수 있나' 를 가른다 (#563)")
    void otherPeoplesDogsAreMarked() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        dog(mom, "보리");
        dog(dad, "뭉치");
        JsonNode group = createGroup(mom, "보리네");
        join(dad, invite(mom, group.path("roomId").asLong()));

        JsonNode dogs = body(familyDogs(dad, group.path("id").asLong()));

        assertThat(mineFlags(dogs))
                .as("이 값이 없으면 아빠가 스위처에서 보리를 고르고 \"우리 아이 정보 관리\" 를"
                        + " 눌렀을 때 그제서야 404 를 만난다")
                .containsExactly(entry("보리", false), entry("뭉치", true));

        assertThat(mineFlags(body(mockMvc.perform(get("/api/dogs")
                        .header("Authorization", "Bearer " + dad.token())))))
                .as("내 아이 목록은 늘 true 다 — 경로마다 다른 뜻이 되면 안 된다")
                .containsExactly(entry("뭉치", true));
    }

    @Test
    @DisplayName("내가 등록한 아이 목록은 안 변한다 — 두 경로가 다른 질문에 답한다")
    void myOwnListIsUnchanged() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        dog(mom, "보리");
        JsonNode group = createGroup(mom, "보리네");
        join(dad, invite(mom, group.path("roomId").asLong()));

        assertThat(names(body(mockMvc.perform(get("/api/dogs")
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isOk()))))
                .as("GET /api/dogs 는 '고칠 수 있는 아이' 다 — 여기가 늘어나면 아빠가 보리를 고칠 수 있다고 읽힌다")
                .isEmpty();
    }

    @Test
    @DisplayName("식구가 아니면 403 — 없는 그룹도 같은 403 이다")
    void strangersAndMissingGroupsGetTheSame403() throws Exception {
        Account mom = account("엄마");
        Account stranger = account("남");
        dog(mom, "보리");
        JsonNode group = createGroup(mom, "보리네");

        familyDogs(stranger, group.path("id").asLong()).andExpect(status().isForbidden());
        // 404 로 답하면 id 를 훑어 있는 가족과 없는 가족을 가려낼 수 있다.
        familyDogs(stranger, 9_999_999L).andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("아이가 한 마리도 없는 집은 빈 배열이다 — 오류가 아니다")
    void aFamilyWithNoDogsGetsAnEmptyArray() throws Exception {
        Account mom = account("엄마");
        JsonNode group = createGroup(mom, "보리네");

        JsonNode dogs = body(familyDogs(mom, group.path("id").asLong()).andExpect(status().isOk()));

        assertThat(dogs.isArray()).isTrue();
        assertThat(dogs).isEmpty();
    }

    @Test
    @DisplayName("지운 아이는 안 온다")
    void deletedDogsDoNotCome() throws Exception {
        Account mom = account("엄마");
        long bori = dog(mom, "보리");
        dog(mom, "누리");
        JsonNode group = createGroup(mom, "보리네");

        mockMvc.perform(delete("/api/dogs/{dogId}", bori)
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isNoContent());

        assertThat(names(body(familyDogs(mom, group.path("id").asLong())))).containsExactly("누리");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("familydogs-%d-%d@example.com".formatted(System.nanoTime(), serial))
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

    private JsonNode createGroup(Account owner, String name) throws Exception {
        return body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\"}".formatted(name)))
                .andExpect(status().isCreated()));
    }

    private String invite(Account owner, long roomId) throws Exception {
        return body(mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isCreated())).path("code").asText();
    }

    private void join(Account account, String code) throws Exception {
        mockMvc.perform(post("/api/chat/invites/{code}/join", code)
                        .header("Authorization", "Bearer " + account.token()))
                .andExpect(status().isOk());
    }

    private ResultActions familyDogs(Account account, long groupId) throws Exception {
        return mockMvc.perform(get("/api/groups/{groupId}/dogs", groupId)
                .header("Authorization", "Bearer " + account.token()));
    }

    /** {@code 이름 -> mine} 순서 그대로. */
    private List<java.util.Map.Entry<String, Boolean>> mineFlags(JsonNode array) {
        return java.util.stream.StreamSupport.stream(array.spliterator(), false)
                .map(node -> java.util.Map.entry(
                        node.path("name").asText(), node.path("mine").asBoolean()))
                .toList();
    }

    private List<String> names(JsonNode array) {
        return java.util.stream.StreamSupport.stream(array.spliterator(), false)
                .map(node -> node.path("name").asText())
                .toList();
    }

    private JsonNode body(ResultActions actions) throws Exception {
        MockHttpServletResponse response = actions.andReturn().getResponse();
        return objectMapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }
}
