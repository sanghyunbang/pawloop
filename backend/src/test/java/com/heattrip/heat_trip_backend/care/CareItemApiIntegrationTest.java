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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 목록을 고치는 다섯 경로를 <b>실제로 부른다</b> — 이슈 #560 조각 2.
 *
 * <h2>왜 계약 검사만으로는 모자란가</h2>
 *
 * <p>{@code CareItemContractSpecTest} 는 문서와 클래스를 대조할 뿐 <b>요청을 보내지 않는다.</b>
 * 그래서 라우팅({@code /order} 가 {@code itemId} 로 읽히는가) · 인가(옆집 목록이 보이는가) ·
 * 경계(20자 넘는 이름) 는 거기서 안 잡힌다. 여기가 그 자리다.
 *
 * <p>아이디는 {@code AtomicLong} 으로 흘린다 — 한 계정에 여러 별명을 붙이면 "누가 했나" 를
 * 재는 단언이 통째로 거짓이 된다(#570 에서 겪었다).
 */
@SpringBootTest
@AutoConfigureMockMvc
class CareItemApiIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;

    // ─────────────────────────── 읽기 ───────────────────────────

    @Test
    @DisplayName("가족을 만들면 목록에 기본 일곱이 순서대로 온다 — 첫 화면이 비면 안 된다")
    void theListStartsWithTheSeven() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        assertThat(names(list(mom, groupId)))
                .containsExactly("물", "밥", "산책", "투약", "병원", "배변", "마킹");
    }

    @Test
    @DisplayName("옆집 목록은 안 보인다 — 인가가 요청을 통째로 막는다")
    void theNeighbourCannotRead() throws Exception {
        Account mom = account("엄마");
        Account neighbour = account("이웃");
        long ours = createGroup(mom);
        createGroup(neighbour);

        mockMvc.perform(get(base(ours))
                        .header("Authorization", "Bearer " + neighbour.token()))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("토큰이 없으면 401 이다")
    void anonymousIsRejected() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        mockMvc.perform(get(base(groupId))).andExpect(status().isUnauthorized());
    }

    // ─────────────────────────── 만들기 ───────────────────────────

    @Test
    @DisplayName("항목을 만들면 맨 뒤에 붙는다 — 매일 보는 순서가 만들 때마다 흔들리면 안 된다")
    void newItemsGoToTheEnd() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        JsonNode created = create(mom, groupId, """
                {"name":"양치","icon":"tooth"}""");

        assertThat(created.path("sortOrder").asInt()).isEqualTo(7);
        assertThat(created.path("systemType").isNull())
                .as("직접 만든 항목이 종류를 가지면 옛 기록이 두 칸에서 세어진다")
                .isTrue();
        assertThat(names(list(mom, groupId))).last().isEqualTo("양치");
    }

    @Test
    @DisplayName("이름이 비었거나 20자를 넘으면 400 이다 — 잘라서 저장하지 않는다")
    void nameIsBoundedOnBothSides() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        rejected(mom, groupId, """
                {"name":"   ","icon":"tooth"}""");
        rejected(mom, groupId, """
                {"name":"%s","icon":"tooth"}""".formatted("가".repeat(21)));

        assertThat(create(mom, groupId, """
                {"name":"  양치  ","icon":"tooth"}""").path("name").asText())
                .as("앞뒤 공백은 잘라서 본다 — 공백만 다른 이름 둘이 목록에 나란히 서면 안 된다")
                .isEqualTo("양치");
    }

    @Test
    @DisplayName("고르는 목록 밖의 아이콘은 400 이다 — 이모지 자유 입력이 아니다")
    void iconMustComeFromTheList() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        rejected(mom, groupId, """
                {"name":"양치","icon":"🪥"}""");
        rejected(mom, groupId, """
                {"name":"양치","icon":"toothbrush"}""");
    }

    @Test
    @DisplayName("하루 목표는 1~20 이다 — 0 은 접기이고 999 는 그릴 자리가 없다")
    void dailyTargetIsBounded() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);

        rejected(mom, groupId, """
                {"name":"양치","icon":"tooth","dailyTarget":0}""");
        rejected(mom, groupId, """
                {"name":"양치","icon":"tooth","dailyTarget":21}""");

        assertThat(create(mom, groupId, """
                {"name":"양치","icon":"tooth","dailyTarget":2}""").path("dailyTarget").asInt())
                .isEqualTo(2);
    }

    @Test
    @DisplayName("옆집 아이를 붙이면 400 이다 — 인가를 지나도 남의 아이는 못 고른다")
    void aNeighboursDogIsRejected() throws Exception {
        Account mom = account("엄마");
        Account neighbour = account("이웃");
        long ours = createGroup(mom);
        createGroup(neighbour);
        long theirDog = registerDog(neighbour, "옆집보리");

        rejected(mom, ours, """
                {"name":"심장사상충 약","icon":"heart","dogId":%d}""".formatted(theirDog));
    }

    @Test
    @DisplayName("우리 집 아이는 붙는다 — 등록한 사람이 누구인지는 안 따진다")
    void ourDogCanBeChosen() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long dogId = registerDog(mom, "보리");

        assertThat(create(mom, groupId, """
                {"name":"심장사상충 약","icon":"heart","dogId":%d}""".formatted(dogId))
                .path("dogId").asLong())
                .isEqualTo(dogId);
    }

    // ─────────────────────────── 고치기 ───────────────────────────

    @Test
    @DisplayName("기본 항목의 이름도 바뀐다 — 종류는 그대로라 어제 기록이 새 이름으로 보인다")
    void theDefaultsAreEditableToo() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        JsonNode meal = list(mom, groupId).get(1);

        JsonNode after = replace(mom, groupId, meal.path("id").asLong(), """
                {"name":"아침밥","icon":"meal"}""");

        assertThat(after.path("name").asText()).isEqualTo("아침밥");
        assertThat(after.path("systemType").asText())
                .as("종류가 바뀌면 지난 기록이 통째로 다른 칸으로 옮겨 간다")
                .isEqualTo("meal");
    }

    @Test
    @DisplayName("고치기는 전량 교체다 — 안 보낸 목표는 비워진다")
    void replacingClearsWhatIsNotSent() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long itemId = create(mom, groupId, """
                {"name":"양치","icon":"tooth","dailyTarget":2}""").path("id").asLong();

        assertThat(replace(mom, groupId, itemId, """
                {"name":"양치","icon":"tooth"}""").path("dailyTarget").isNull())
                .as("""
                        PATCH 였다면 '안 보냄' 과 '비우려고 보냄' 이 둘 다 null 이라 목표를 지울 \
                        방법이 없다. PUT 이라 이 단언이 성립한다.""")
                .isTrue();
    }

    @Test
    @DisplayName("옆집 항목은 404 다 — 없는 것과 남의 것이 같은 답이다")
    void aNeighboursItemIsNotFound() throws Exception {
        Account mom = account("엄마");
        Account neighbour = account("이웃");
        long ours = createGroup(mom);
        long theirs = createGroup(neighbour);
        long theirItem = list(neighbour, theirs).get(0).path("id").asLong();

        mockMvc.perform(put(base(ours) + "/" + theirItem)
                        .header("Authorization", "Bearer " + mom.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"뺏기","icon":"etc"}"""))
                .andExpect(status().isNotFound());

        assertThat(names(list(neighbour, theirs))).first()
                .as("옆집 목록이 한 글자도 안 바뀌어야 한다")
                .isEqualTo("물");
    }

    // ─────────────────────────── 접기 ───────────────────────────

    @Test
    @DisplayName("접어도 목록에 남는다 — 다시 켤 방법이 화면에서 사라지면 안 된다")
    void archivingKeepsTheRow() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long medId = list(mom, groupId).get(3).path("id").asLong();

        mockMvc.perform(delete(base(groupId) + "/" + medId)
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isNoContent());

        List<JsonNode> after = list(mom, groupId);
        assertThat(after).hasSize(7);
        assertThat(after.get(3).path("archivedAt").isNull()).isFalse();
    }

    @Test
    @DisplayName("두 번 접어도 204 이고 접은 시각은 처음 것이다 — 재시도가 기록을 안 흔든다")
    void archivingTwiceIsQuiet() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long medId = list(mom, groupId).get(3).path("id").asLong();

        archive(mom, groupId, medId);
        String first = list(mom, groupId).get(3).path("archivedAt").asText();
        archive(mom, groupId, medId);

        assertThat(list(mom, groupId).get(3).path("archivedAt").asText()).isEqualTo(first);
    }

    @Test
    @DisplayName("archived:false 로 다시 켜진다")
    void archivedFalseRestoresIt() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long medId = list(mom, groupId).get(3).path("id").asLong();
        archive(mom, groupId, medId);

        assertThat(replace(mom, groupId, medId, """
                {"name":"투약","icon":"med","archived":false}""").path("archivedAt").isNull())
                .isTrue();
    }

    @Test
    @DisplayName("이름만 고쳐도 접은 시각은 안 바뀐다 — 언제부터 안 하고 있었는지가 사라지면 안 된다")
    void editingAnArchivedItemKeepsWhenItWasArchived() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        long medId = list(mom, groupId).get(3).path("id").asLong();
        archive(mom, groupId, medId);
        String archivedAt = list(mom, groupId).get(3).path("archivedAt").asText();

        assertThat(replace(mom, groupId, medId, """
                {"name":"먹는 약","icon":"med","archived":true}""").path("archivedAt").asText())
                .isEqualTo(archivedAt);
    }

    // ─────────────────────────── 순서 ───────────────────────────

    @Test
    @DisplayName("보낸 순서대로 다시 온다 — order 가 itemId 로 읽히지 않는다")
    void reorderingRewritesTheList() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        List<Long> ids = ids(list(mom, groupId));

        List<Long> reversed = new ArrayList<>(ids);
        java.util.Collections.reverse(reversed);
        reorder(mom, groupId, reversed).andExpect(status().isNoContent());

        assertThat(ids(list(mom, groupId)))
                .as("/order 가 {itemId} 로 잡히면 여기까지 오지도 못하고 400 이다")
                .isEqualTo(reversed);
        assertThat(names(list(mom, groupId))).first().isEqualTo("마킹");
    }

    @Test
    @DisplayName("하나라도 빠지면 400 이다 — 조용히 뒤에 붙이면 남의 새 항목이 맨 뒤로 밀린다")
    void aMissingIdIsRejected() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        List<Long> ids = ids(list(mom, groupId));

        reorder(mom, groupId, ids.subList(0, 6)).andExpect(status().isBadRequest());
        assertThat(names(list(mom, groupId))).first()
                .as("거절했으면 한 행도 안 바뀌어야 한다")
                .isEqualTo("물");
    }

    @Test
    @DisplayName("같은 id 가 두 번이면 400 이다")
    void aDuplicateIdIsRejected() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        List<Long> ids = ids(list(mom, groupId));

        List<Long> duplicated = new ArrayList<>(ids.subList(0, 6));
        duplicated.add(ids.get(0));
        reorder(mom, groupId, duplicated).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("옆집 항목 id 를 섞으면 400 이다")
    void aNeighboursIdIsRejected() throws Exception {
        Account mom = account("엄마");
        Account neighbour = account("이웃");
        long ours = createGroup(mom);
        long theirs = createGroup(neighbour);

        List<Long> mixed = new ArrayList<>(ids(list(mom, ours)).subList(0, 6));
        mixed.add(ids(list(neighbour, theirs)).get(0));
        reorder(mom, ours, mixed).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("접힌 항목도 순서에 든다 — 다시 켰을 때 맨 뒤로 튀면 안 된다")
    void archivedItemsKeepTheirSlot() throws Exception {
        Account mom = account("엄마");
        long groupId = createGroup(mom);
        List<Long> ids = ids(list(mom, groupId));
        archive(mom, groupId, ids.get(3));

        List<Long> moved = new ArrayList<>(ids);
        moved.remove(3);
        moved.add(0, ids.get(3));
        reorder(mom, groupId, moved).andExpect(status().isNoContent());

        assertThat(ids(list(mom, groupId)).get(0)).isEqualTo(ids.get(3));
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static String base(long groupId) {
        return "/api/groups/" + groupId + "/care-items";
    }

    private List<JsonNode> list(Account actor, long groupId) throws Exception {
        JsonNode array = body(mockMvc.perform(get(base(groupId))
                        .header("Authorization", "Bearer " + actor.token()))
                .andExpect(status().isOk()));
        List<JsonNode> out = new ArrayList<>();
        array.forEach(out::add);
        return out;
    }

    private static List<String> names(List<JsonNode> items) {
        return items.stream().map(item -> item.path("name").asText()).toList();
    }

    private static List<Long> ids(List<JsonNode> items) {
        return items.stream().map(item -> item.path("id").asLong()).toList();
    }

    private JsonNode create(Account actor, long groupId, String json) throws Exception {
        return body(mockMvc.perform(post(base(groupId))
                        .header("Authorization", "Bearer " + actor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isCreated()));
    }

    private void rejected(Account actor, long groupId, String json) throws Exception {
        mockMvc.perform(post(base(groupId))
                        .header("Authorization", "Bearer " + actor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isBadRequest());
    }

    private JsonNode replace(Account actor, long groupId, long itemId, String json)
            throws Exception {
        return body(mockMvc.perform(put(base(groupId) + "/" + itemId)
                        .header("Authorization", "Bearer " + actor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isOk()));
    }

    private void archive(Account actor, long groupId, long itemId) throws Exception {
        mockMvc.perform(delete(base(groupId) + "/" + itemId)
                        .header("Authorization", "Bearer " + actor.token()))
                .andExpect(status().isNoContent());
    }

    private ResultActions reorder(Account actor, long groupId, List<Long> itemIds)
            throws Exception {
        return mockMvc.perform(put(base(groupId) + "/order")
                .header("Authorization", "Bearer " + actor.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(objectMapper.writeValueAsString(
                        java.util.Map.of("itemIds", itemIds))));
    }

    private long registerDog(Account owner, String name) throws Exception {
        return body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s","species":"dog","size":"small"}""".formatted(name)))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("careitemapi-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
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
