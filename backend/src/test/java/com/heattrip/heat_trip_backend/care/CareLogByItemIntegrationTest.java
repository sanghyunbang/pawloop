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
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 오늘의 케어가 <b>항목 기준</b>으로 읽히고 쓰인다 — 이슈 #560 조각 2.
 *
 * <h2>무엇을 보증하나</h2>
 *
 * <p>이 PR 의 약속은 하나다 — <b>앱이 "어느 칸의 기록인가" 를 다시 계산하지 않는다.</b>
 * 서버가 {@code careItemId} 를 풀어서 준다. 그 갈래(기본 일곱은 {@code type} 으로, 직접 만든
 * 것은 {@code care_item_id} 로)가 앱에도 적히면 규칙이 두 곳에 생기고, 그때부터 한쪽만
 * 고쳐지는 날을 기다리게 된다.
 *
 * <p>그리고 <b>옛 기록을 한 행도 안 건드린다</b>는 약속. 이 컬럼이 생기기 전의 행과 산책
 * 트래킹이 {@code type='walk'} 로 남기는 행이 그대로 제 칸에 세어져야 한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CareLogByItemIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;

    // ─────────────────────────── 쓰기 ───────────────────────────

    @Test
    @DisplayName("직접 만든 항목에 기록이 남는다 — 종류는 비고 항목만 든다")
    void aCustomItemCanBeRecorded() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long tooth = createItem(mom, groupId, "양치", "tooth");

        JsonNode log = record(mom, groupId, """
                {"careItemId":%d}""".formatted(tooth));

        assertThat(log.path("type").isNull())
                .as("일곱 중 아무거나 넣으면 그 칸이 양치 기록을 함께 센다")
                .isTrue();
        assertThat(log.path("careItemId").asLong()).isEqualTo(tooth);
    }

    @Test
    @DisplayName("기본 항목을 누르면 서버가 종류를 함께 적는다 — 옛 기록과 같은 축이어야 한다")
    void aSystemItemAlsoGetsItsType() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long meal = itemIdOf(mom, groupId, "밥");

        JsonNode log = record(mom, groupId, """
                {"careItemId":%d}""".formatted(meal));

        assertThat(log.path("type").asText())
                .as("""
                        종류를 안 적으면 산책 화면의 type='walk' 조회와 옛 기록 집계가 이 행을 \
                        못 본다 — 같은 일을 두 축으로 세게 된다.""")
                .isEqualTo("meal");
        assertThat(log.path("careItemId").asLong()).isEqualTo(meal);
    }

    @Test
    @DisplayName("종류만 보내는 길은 그대로다 — 이미 나가 있는 앱과 산책 트래킹이 이 경로다")
    void theTypeOnlyPathStillWorks() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        JsonNode log = record(mom, groupId, """
                {"type":"walk"}""");

        assertThat(log.path("type").asText()).isEqualTo("walk");
        assertThat(log.path("careItemId").asLong())
                .as("행에는 항목이 안 적혀 있지만, 서버가 그 집의 '산책' 칸으로 풀어서 준다")
                .isEqualTo(itemIdOf(mom, groupId, "산책"));
    }

    @Test
    @DisplayName("둘 다 없으면 400 이다 — 어느 칸의 기록도 아닌 행은 지울 수도 없다")
    void neitherIsRejected() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        rejected(mom, groupId, "{}");
    }

    @Test
    @DisplayName("둘 다 보내도 400 이다 — 어느 쪽을 믿을지 정하면 하나가 조용히 버려진다")
    void bothIsRejected() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long tooth = createItem(mom, groupId, "양치", "tooth");

        rejected(mom, groupId, """
                {"type":"meal","careItemId":%d}""".formatted(tooth));
    }

    @Test
    @DisplayName("옆집 항목 id 로는 못 남긴다 — 없는 항목과 같은 404 다")
    void aNeighboursItemIsNotFound() throws Exception {
        Account mom = account("엄마");
        Account neighbour = account("이웃");
        long ours = createGroup(mom);
        long theirs = createGroup(neighbour);
        long theirItem = itemIdOf(neighbour, theirs, "밥");

        mockMvc.perform(post(logs(ours))
                        .header("Authorization", "Bearer " + mom.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"careItemId":%d}""".formatted(theirItem)))
                .andExpect(status().isNotFound());
    }

    // ─────────────────────────── 읽기 ───────────────────────────

    @Test
    @DisplayName("하루치 목록의 모든 줄이 제 칸을 든다 — 앱이 다시 계산하지 않는다")
    void everyLogCarriesItsItem() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long tooth = createItem(mom, groupId, "양치", "tooth");
        record(mom, groupId, """
                {"type":"meal"}""");
        record(mom, groupId, """
                {"careItemId":%d}""".formatted(tooth));

        List<JsonNode> today = logs(mom, groupId);

        assertThat(today).hasSize(2);
        assertThat(today).allSatisfy(log -> assertThat(log.path("careItemId").isNull())
                .as("한 줄이라도 비면 그 기록은 카드 어디에도 안 뜬다")
                .isFalse());
        assertThat(today.stream().map(log -> log.path("careItemId").asLong()).toList())
                .containsExactlyInAnyOrder(itemIdOf(mom, groupId, "밥"), tooth);
    }

    @Test
    @DisplayName("이름을 바꿔도 어제 기록이 그 칸에 그대로 있다 — 이름은 기록에 안 적힌다")
    void renamingAnItemKeepsItsLogs() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long meal = itemIdOf(mom, groupId, "밥");
        record(mom, groupId, """
                {"type":"meal"}""");

        replaceItem(mom, groupId, meal, """
                {"name":"아침밥","icon":"meal"}""");

        assertThat(logs(mom, groupId).get(0).path("careItemId").asLong())
                .as("care_log 는 이름을 저장하지 않는다 — 고치면 옛 기록도 새 이름으로 보인다")
                .isEqualTo(meal);
    }

    @Test
    @DisplayName("접은 항목의 기록도 제 칸을 든다 — 접어도 기록은 쌓인다")
    void anArchivedItemStillOwnsItsLogs() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long walk = itemIdOf(mom, groupId, "산책");
        archiveItem(mom, groupId, walk);

        record(mom, groupId, """
                {"type":"walk"}""");

        assertThat(logs(mom, groupId).get(0).path("careItemId").asLong())
                .as("""
                        산책처럼 다른 화면이 자동으로 쓰는 항목은 접어도 기록이 계속 쌓인다 — \
                        나중에 다시 켜면 그동안의 기록이 그대로 있어야 한다.""")
                .isEqualTo(walk);
    }

    @Test
    @DisplayName("옆집 항목 번호는 절대 안 섞인다 — 같은 종류라도 그 집 칸이다")
    void theNeighboursItemIdNeverLeaks() throws Exception {
        Account mom = account("엄마");
        Account neighbour = account("이웃");
        long ours = createGroup(mom);
        long theirs = createGroup(neighbour);
        record(mom, ours, """
                {"type":"meal"}""");

        long ourMeal = itemIdOf(mom, ours, "밥");
        long theirMeal = itemIdOf(neighbour, theirs, "밥");

        assertThat(ourMeal).isNotEqualTo(theirMeal);
        assertThat(logs(mom, ours).get(0).path("careItemId").asLong()).isEqualTo(ourMeal);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static String logs(long groupId) {
        return "/api/groups/" + groupId + "/care-logs";
    }

    private static String items(long groupId) {
        return "/api/groups/" + groupId + "/care-items";
    }

    private JsonNode record(Account actor, long groupId, String json) throws Exception {
        return body(mockMvc.perform(post(logs(groupId))
                        .header("Authorization", "Bearer " + actor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isCreated()));
    }

    private void rejected(Account actor, long groupId, String json) throws Exception {
        mockMvc.perform(post(logs(groupId))
                        .header("Authorization", "Bearer " + actor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isBadRequest());
    }

    private List<JsonNode> logs(Account actor, long groupId) throws Exception {
        JsonNode array = body(mockMvc.perform(get(logs(groupId))
                        .header("Authorization", "Bearer " + actor.token()))
                .andExpect(status().isOk()));
        List<JsonNode> out = new ArrayList<>();
        array.forEach(out::add);
        return out;
    }

    private long createItem(Account actor, long groupId, String name, String icon)
            throws Exception {
        return body(mockMvc.perform(post(items(groupId))
                        .header("Authorization", "Bearer " + actor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s","icon":"%s"}""".formatted(name, icon)))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private void replaceItem(Account actor, long groupId, long itemId, String json)
            throws Exception {
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                        .put(items(groupId) + "/" + itemId)
                        .header("Authorization", "Bearer " + actor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isOk());
    }

    private void archiveItem(Account actor, long groupId, long itemId) throws Exception {
        mockMvc.perform(org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                        .delete(items(groupId) + "/" + itemId)
                        .header("Authorization", "Bearer " + actor.token()))
                .andExpect(status().isNoContent());
    }

    /** 그 집 목록에서 이름으로 항목 번호를 찾는다 — 기본 일곱은 이름이 정해져 있다. */
    private long itemIdOf(Account actor, long groupId, String name) throws Exception {
        JsonNode array = body(mockMvc.perform(get(items(groupId))
                        .header("Authorization", "Bearer " + actor.token()))
                .andExpect(status().isOk()));
        for (JsonNode item : array) {
            if (name.equals(item.path("name").asText())) {
                return item.path("id").asLong();
            }
        }
        throw new IllegalStateException("그 집 목록에 '" + name + "' 이 없다");
    }

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = consented(users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("carelogitem-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private long createGroup(Account owner) throws Exception {
        return body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"보리네"}"""))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private JsonNode body(ResultActions actions) throws Exception {
        MockHttpServletResponse response = actions.andReturn().getResponse();
        return objectMapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }
}
