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
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 글 저장 — "내 사진첩" (이슈 #451 4번). {@code CommunityIntegrationTest} 와 같은 방식 —
 * 진짜 MySQL(Testcontainers) 위에서 진짜 JWT 로 부른다.
 *
 * <p><b>피드는 전역이다</b> — 다른 테스트의 글이 섞이므로 목록 크기를 재지 않고 내 id 를 찾는다.
 * 저장한 글 목록은 내 것만 오므로 거기서는 순서까지 잰다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class PostBookmarkIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Test
    @DisplayName("저장하면 피드·상세의 bookmarked 가 켜지고, 빼면 꺼진다 — 둘 다 멱등")
    void bookmarkTogglesTheFlagOnFeedAndDetail() throws Exception {
        Account me = account("저장하는사람");
        long postId = newPost(me, "저장할 글");

        assertThat(itemById(body(feed(me)), postId).path("bookmarked").asBoolean())
                .as("아직 안 저장했다").isFalse();

        JsonNode on = body(bookmark(me, postId, true).andExpect(status().isOk()));
        assertThat(on.path("bookmarked").asBoolean()).isTrue();
        assertThat(body(bookmark(me, postId, true).andExpect(status().isOk())).path("bookmarked").asBoolean())
                .as("두 번 저장해도 200 이고 상태는 같다 — 재시도가 안전해야 한다").isTrue();

        assertThat(itemById(body(feed(me)), postId).path("bookmarked").asBoolean()).isTrue();
        assertThat(body(detail(me, postId)).path("bookmarked").asBoolean()).isTrue();

        JsonNode off = body(bookmark(me, postId, false).andExpect(status().isOk()));
        assertThat(off.path("bookmarked").asBoolean()).isFalse();
        assertThat(body(bookmark(me, postId, false).andExpect(status().isOk())).path("bookmarked").asBoolean())
                .as("안 저장한 것을 빼도 200 이다").isFalse();
        assertThat(itemById(body(feed(me)), postId).path("bookmarked").asBoolean()).isFalse();
    }

    @Test
    @DisplayName("내가 저장한 글 목록은 저장한 순이고 남의 저장은 안 섞인다 — 커서로 다음 장까지")
    void myBookmarksAreOrderedBySaveTimeAndPrivate() throws Exception {
        Account me = account("사진첩주인");
        Account other = account("남");
        long first = newPost(other, "먼저 저장할 글");
        long second = newPost(other, "나중에 저장할 글");
        long third = newPost(other, "마지막에 저장할 글");
        long theirs = newPost(me, "남이 저장한 글");

        bookmark(me, first, true).andExpect(status().isOk());
        bookmark(me, second, true).andExpect(status().isOk());
        bookmark(me, third, true).andExpect(status().isOk());
        bookmark(other, theirs, true).andExpect(status().isOk());

        JsonNode page1 = body(bookmarks(me, "?limit=2").andExpect(status().isOk()));
        assertThat(idsOf(page1))
                .as("저장한 순의 역순 — 글이 쓰인 순이 아니라 마지막에 저장한 것이 먼저다")
                .containsExactly(third, second);
        assertThat(page1.path("hasMore").asBoolean()).isTrue();
        assertThat(page1.path("items").get(0).path("bookmarked").asBoolean())
                .as("저장한 글 목록의 항목은 전부 저장된 상태다").isTrue();

        JsonNode page2 = body(bookmarks(me, "?limit=2&cursor=" + page1.path("nextCursor").asText())
                .andExpect(status().isOk()));
        assertThat(idsOf(page2)).containsExactly(first);
        assertThat(page2.path("hasMore").asBoolean()).isFalse();
        assertThat(idsOf(page1)).doesNotContain(theirs);
        assertThat(idsOf(page2)).as("남의 저장은 내 목록에 없다").doesNotContain(theirs);
    }

    @Test
    @DisplayName("빼면 목록에서 사라지고, 글이 지워지면 저장도 함께 사라진다")
    void removedAndDeletedPostsLeaveTheList() throws Exception {
        Account me = account("정리하는사람");
        long kept = newPost(me, "남길 글");
        long unsaved = newPost(me, "뺄 글");
        long deleted = newPost(me, "지울 글");
        bookmark(me, kept, true).andExpect(status().isOk());
        bookmark(me, unsaved, true).andExpect(status().isOk());
        bookmark(me, deleted, true).andExpect(status().isOk());

        bookmark(me, unsaved, false).andExpect(status().isOk());
        mockMvc.perform(delete("/api/community/posts/" + deleted)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNoContent());

        assertThat(idsOf(body(bookmarks(me, "").andExpect(status().isOk()))))
                .containsExactly(kept);
    }

    @Test
    @DisplayName("게스트는 피드에서 bookmarked 가 false 이고, 저장·목록은 401 이다")
    void guestsCannotBookmark() throws Exception {
        Account author = account("글쓴이");
        long postId = newPost(author, "게스트가 보는 글");

        JsonNode guestFeed = body(mockMvc.perform(get("/api/community/posts")).andExpect(status().isOk()));
        assertThat(itemById(guestFeed, postId).path("bookmarked").asBoolean()).isFalse();
        assertThat(itemById(guestFeed, postId).path("bookmarked").isBoolean())
                .as("게스트에게도 필드는 있다 — null 이 아니라 false 다").isTrue();

        mockMvc.perform(post("/api/community/posts/" + postId + "/bookmark"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/community/bookmarks"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("없는 글은 404 다 — 저장도 빼기도")
    void missingPostIsNotFound() throws Exception {
        Account me = account("없는글");

        bookmark(me, 987654321L, true).andExpect(status().isNotFound());
        bookmark(me, 987654321L, false).andExpect(status().isNotFound());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ResultActions bookmark(Account account, long postId, boolean on) throws Exception {
        String path = "/api/community/posts/" + postId + "/bookmark";
        return mockMvc.perform((on ? post(path) : delete(path))
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions bookmarks(Account account, String query) throws Exception {
        return mockMvc.perform(get("/api/community/bookmarks" + query)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions feed(Account account) throws Exception {
        return mockMvc.perform(get("/api/community/posts")
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions detail(Account account, long postId) throws Exception {
        return mockMvc.perform(get("/api/community/posts/" + postId)
                .header("Authorization", "Bearer " + account.token()));
    }

    private long newPost(Account account, String title) throws Exception {
        JsonNode created = body(mockMvc.perform(post("/api/community/posts")
                        .header("Authorization", "Bearer " + account.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"board\":\"free\",\"title\":\"" + title + "\",\"body\":\"본문\"}"))
                .andExpect(status().isCreated()));
        return created.path("id").asLong();
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("bookmark-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
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
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(StandardCharsets.UTF_8));
    }

    private record Account(long id, String token) { }
}
