package com.heattrip.heat_trip_backend.community;

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
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 글에 찍힌 아이 — "아이 사진첩" (이슈 #451 5번). {@code CommunityIntegrationTest} 와 같은 방식 —
 * 진짜 MySQL 위에서 진짜 JWT 로 부른다. 피드는 전역이라 목록 크기를 재지 않고 내 id 를 찾는다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class PostDogIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private JdbcTemplate jdbc;

    @Test
    @DisplayName("내 아이를 붙여 쓰면 응답·목록·상세에 아이 꼬리표(id·이름·사진)가 온다 — 안 붙이면 null")
    void postCarriesItsDog() throws Exception {
        Account me = account("보리아빠");
        long bori = newDog(me, "보리");
        jdbc.update("update dog set avatar = ? where id = ?", "profiles/1/bori.jpg", bori);

        JsonNode created = body(createPost(me, "{\"board\":\"brag\",\"title\":\"보리 사진\",\"body\":\"본문\",\"dogId\":" + bori + "}")
                .andExpect(status().isCreated()));
        assertThat(created.path("dog").path("id").asLong()).isEqualTo(bori);
        assertThat(created.path("dog").path("name").asText()).isEqualTo("보리");
        assertThat(created.path("dog").path("avatarUrl").asText())
                .as("꼬리표의 사진은 키가 아니라 공개 URL 이다")
                .endsWith("profiles/1/bori.jpg").startsWith("http");
        long postId = created.path("id").asLong();

        assertThat(itemById(body(feed(me, "")), postId).path("dog").path("name").asText()).isEqualTo("보리");
        assertThat(body(detail(me, postId)).path("dog").path("id").asLong()).isEqualTo(bori);

        JsonNode plain = body(createPost(me, "{\"board\":\"free\",\"title\":\"아이 없이\",\"body\":\"본문\"}")
                .andExpect(status().isCreated()));
        assertThat(plain.path("dog").isNull()).as("안 골랐으면 null — 빈 객체가 아니다").isTrue();
    }

    @Test
    @DisplayName("남의 아이는 못 붙인다 — 400. 404 로 가르면 남의 아이 id 를 훑을 수 있다")
    void rejectsSomeoneElsesDog() throws Exception {
        Account me = account("나");
        Account other = account("남");
        long theirs = newDog(other, "남의개");

        createPost(me, "{\"board\":\"free\",\"title\":\"글\",\"body\":\"본문\",\"dogId\":" + theirs + "}")
                .andExpect(status().isBadRequest());
        createPost(me, "{\"board\":\"free\",\"title\":\"글\",\"body\":\"본문\",\"dogId\":987654321}")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("?dogId= 는 그 아이의 글만 준다 — 다른 아이 · 아이 없는 글은 빠지고, board 와 함께 쓸 수 있다")
    void feedFiltersByDog() throws Exception {
        Account me = account("사진첩주인");
        long bori = newDog(me, "보리");
        long tan = newDog(me, "탄이");
        long boriPost = postId(me, "brag", "보리 1", bori);
        long boriFree = postId(me, "free", "보리 2", bori);
        long tanPost = postId(me, "brag", "탄이 1", tan);
        long noDog = postId(me, "brag", "아이 없음", null);

        List<Long> ids = idsOf(body(feed(me, "?dogId=" + bori).andExpect(status().isOk())));
        assertThat(ids).contains(boriPost, boriFree).doesNotContain(tanPost, noDog);

        List<Long> bragOnly = idsOf(body(feed(me, "?dogId=" + bori + "&board=brag").andExpect(status().isOk())));
        assertThat(bragOnly).contains(boriPost).doesNotContain(boriFree, tanPost);

        assertThat(idsOf(body(feed(me, "?dogId=" + tan))).get(0)).isEqualTo(tanPost);
    }

    @Test
    @DisplayName("게스트도 아이로 좁힐 수 있다 — 글은 공개고, 남의 아이 id 도 400 이 아니다")
    void guestsCanFilterByAnyDog() throws Exception {
        Account owner = account("글쓴이");
        long dog = newDog(owner, "보리");
        long postId = postId(owner, "brag", "공개 글", dog);

        JsonNode page = body(mockMvc.perform(get("/api/community/posts?dogId=" + dog)).andExpect(status().isOk()));
        assertThat(idsOf(page)).contains(postId);
    }

    @Test
    @DisplayName("고치기로 아이를 바꿀 수 있고, 키가 없으면 그대로다")
    void patchChangesTheDog() throws Exception {
        Account me = account("고치는사람");
        long bori = newDog(me, "보리");
        long tan = newDog(me, "탄이");
        long postId = postId(me, "brag", "글", bori);

        JsonNode patched = body(patchPost(me, postId, "{\"dogId\":" + tan + "}").andExpect(status().isOk()));
        assertThat(patched.path("dog").path("id").asLong()).isEqualTo(tan);

        JsonNode untouched = body(patchPost(me, postId, "{\"title\":\"제목만\"}").andExpect(status().isOk()));
        assertThat(untouched.path("dog").path("id").asLong()).as("키가 없으면 안 바꾼다").isEqualTo(tan);

        Account other = account("남");
        long theirs = newDog(other, "남의개");
        patchPost(me, postId, "{\"dogId\":" + theirs + "}").andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("아이를 보내면(소프트 삭제) 글은 남고 꼬리표만 사라진다")
    void deletedDogDropsTheTag() throws Exception {
        Account me = account("이별");
        long dog = newDog(me, "하늘");
        long postId = postId(me, "brag", "하늘 사진", dog);

        mockMvc.perform(delete("/api/dogs/{dogId}", dog)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNoContent());

        JsonNode detail = body(detail(me, postId));
        assertThat(detail.path("title").asText()).isEqualTo("하늘 사진");
        assertThat(detail.path("dog").isNull()).as("이름만 남은 꼬리표는 헛갈린다").isTrue();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ResultActions createPost(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/community/posts")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private long postId(Account account, String board, String title, Long dogId) throws Exception {
        String json = "{\"board\":\"" + board + "\",\"title\":\"" + title + "\",\"body\":\"본문\""
                + (dogId == null ? "" : ",\"dogId\":" + dogId) + "}";
        return body(createPost(account, json).andExpect(status().isCreated())).path("id").asLong();
    }

    private ResultActions patchPost(Account account, long postId, String json) throws Exception {
        return mockMvc.perform(patch("/api/community/posts/{id}", postId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions feed(Account account, String query) throws Exception {
        return mockMvc.perform(get("/api/community/posts" + query)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions detail(Account account, long postId) throws Exception {
        return mockMvc.perform(get("/api/community/posts/" + postId)
                .header("Authorization", "Bearer " + account.token()));
    }

    private long newDog(Account who, String name) throws Exception {
        JsonNode created = body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + who.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"species\":\"dog\",\"size\":\"small\"}"))
                .andExpect(status().isCreated()));
        return created.path("id").asLong();
    }

    private static JsonNode itemById(JsonNode page, long postId) {
        for (JsonNode item : page.path("items")) {
            if (item.path("id").asLong() == postId) {
                return item;
            }
        }
        throw new AssertionError("목록에 id=" + postId + " 이 없다. 첫 장 밖으로 밀렸는지 확인하라.");
    }

    private static List<Long> idsOf(JsonNode page) {
        List<Long> ids = new ArrayList<>();
        page.path("items").forEach(p -> ids.add(p.path("id").asLong()));
        return ids;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("postdog-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
