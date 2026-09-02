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
import java.util.HashSet;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 커뮤니티 일곱 경로를 실제로 지나간다 — 이슈 #170.
 *
 * <p>애너테이션이 두 줄뿐인 것은 의도다 — {@code WalkIntegrationTest} ·
 * {@code DogIntegrationTest} 와 글자 그대로 같아야 스프링 컨텍스트 캐시를 공유한다(#21).
 *
 * <h2>피드는 전역이라 테스트끼리 서로의 글을 본다</h2>
 * <p>{@code WalkIntegrationTest} 는 목록이 <b>사용자별</b>이라 "내 것 하나" 를 그대로 셀 수
 * 있었다. 커뮤니티 피드에는 그런 축이 없다 — 같은 컨텍스트를 공유하는 다른 테스트가 만든
 * 글이 같은 목록에 섞인다.
 *
 * <p>그래서 <b>목록의 크기를 세지 않는다.</b> 내가 만든 {@code id} 를 찾아서 그 항목만 본다
 * ({@link #itemById}). 처음에는 크기로 단언했다가 셋이 한꺼번에 빨간불이었고, 그 빨간불이
 * 이 사실을 알려 줬다 — 통과했더라도 그건 실행 순서에 기댄 초록불이었을 것이다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CommunityIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    /** 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    // ─────────────────────────── 일곱 경로 ───────────────────────────

    @Test
    @DisplayName("글을 쓰고, 목록·상세로 읽고, 댓글을 달고, 반응을 켜고 끈다")
    void walksThroughEverySevenPaths() throws Exception {
        Account me = account("보리아빠");

        JsonNode created = body(createPost(me, """
                {"board":"walk_review","title":"서울숲 아침 산책","body":"이른 아침엔 사람이 적어요",
                 "loc":"서울숲","contentId":"126508"}
                """).andExpect(status().isCreated()));
        long postId = created.path("id").asLong();

        assertThat(created.path("author").path("userId").asLong()).isEqualTo(me.id());
        assertThat(created.path("author").path("nickname").asText()).isEqualTo("보리아빠");
        assertThat(created.path("contentId").asText())
                .as("계약이 placeId 가 아니라 contentId 다 — Place.contentId 와 같은 키(ADR-0017)")
                .isEqualTo("126508");
        assertThat(created.path("handle").isMissingNode())
                .as("handle 은 저장 전용이다 — 표시는 현재 닉네임이고 둘을 섞으면 같은 사람의 글이 다른 이름으로 보인다")
                .isTrue();

        JsonNode mineInFeed = itemById(body(feed(me, "").andExpect(status().isOk())), postId);
        assertThat(mineInFeed.path("title").asText()).isEqualTo("서울숲 아침 산책");

        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
        assertThat(detail.path("body").asText()).isEqualTo("이른 아침엔 사람이 적어요");

        addComment(me, postId, "{\"body\":\"저도 자주 가요\"}").andExpect(status().isCreated());
        JsonNode commentPage = body(mockMvc.perform(
                        get("/api/community/posts/" + postId + "/comments"))
                .andExpect(status().isOk()));
        assertThat(commentPage.path("items").size()).isEqualTo(1);
        assertThat(commentPage.path("items").get(0).path("author").path("userId").asLong())
                .as("2026-09 이전 계약의 Comment.author 에는 식별자가 아예 없었다 — '내 댓글인가' 를 못 물었다")
                .isEqualTo(me.id());

        JsonNode afterAdd = body(react(me, postId, "help", true).andExpect(status().isOk()));
        assertThat(afterAdd.path("help").asInt()).isEqualTo(1);
        assertThat(afterAdd.path("mine").size()).isEqualTo(1);

        JsonNode afterRemove = body(react(me, postId, "help", false).andExpect(status().isOk()));
        assertThat(afterRemove.path("help").asInt()).isZero();
        assertThat(afterRemove.path("mine").size()).isZero();

        assertThat(itemById(body(feed(me, "")), postId).path("commentCount").asInt())
                .as("댓글 수는 목록에서 group by 한 번으로 온다")
                .isEqualTo(1);
    }

    // ─────────────────────────── 게스트 읽기 (완료 조건 2·3) ───────────────────────────

    @Test
    @DisplayName("토큰 없이 목록을 읽을 수 있고 reactions.mine 이 null 이다")
    void guestReadsTheFeed_andMineIsNull() throws Exception {
        Account author = account("작성자");
        long postId = body(createPost(author, """
                {"board":"free","title":"게스트도 보이나요","body":"보입니다"}
                """).andExpect(status().isCreated())).path("id").asLong();
        react(author, postId, "cute", true).andExpect(status().isOk());

        JsonNode page = body(mockMvc.perform(get("/api/community/posts"))
                .andExpect(status().isOk()));

        JsonNode reactions = itemById(page, postId).path("reactions");
        assertThat(reactions.path("cute").asInt())
                .as("집계는 게스트에게도 보인다 — 그게 목록의 요점이다")
                .isEqualTo(1);
        assertThat(reactions.path("mine").isNull())
                .as("""
                        null 과 [] 는 다르다. null 은 "물을 대상이 없다"(비인증)이고 \
                        [] 는 "로그인했는데 아무것도 안 눌렀다" 다. 둘을 같게 두면 \
                        []가 게스트에게 거짓말을 한다(ADR-0017 규약 6).""")
                .isTrue();

        assertThat(body(mockMvc.perform(get("/api/community/posts/" + postId))
                .andExpect(status().isOk())).path("reactions").path("mine").isNull()).isTrue();
        mockMvc.perform(get("/api/community/posts/" + postId + "/comments"))
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("토큰 없이 쓰려고 하면 본문 없는 401 이다 — 같은 경로인데 메서드로 갈린다")
    void guestCannotWrite() throws Exception {
        mockMvc.perform(post("/api/community/posts")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"board\":\"free\",\"title\":\"t\",\"body\":\"b\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/community/posts/1/comments")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"body\":\"b\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/community/posts/1/reactions/help"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(delete("/api/community/posts/1/reactions/help"))
                .andExpect(status().isUnauthorized());
    }

    // ─────────────────────────── 반응의 멱등 (ADR-0016 결정 2) ───────────────────────────

    @Test
    @DisplayName("셋을 동시에 누를 수 있다 — 도움돼요·귀여워요·공감은 서로 배타적이지 않다")
    void reactionsAreNotExclusive() throws Exception {
        Account me = account("여러개");
        long postId = newPost(me);

        react(me, postId, "help", true).andExpect(status().isOk());
        react(me, postId, "cute", true).andExpect(status().isOk());
        JsonNode all = body(react(me, postId, "empathy", true).andExpect(status().isOk()));

        assertThat(all.path("mine").size())
                .as("UNIQUE 를 (post_id, user_id) 로 좁히면 여기서 라디오가 된다")
                .isEqualTo(3);
        assertThat(all.path("help").asInt()).isEqualTo(1);
    }

    @Test
    @DisplayName("같은 반응을 두 번 눌러도 200 이고 집계가 안 는다 — 재시도가 안전해야 한다")
    void addingTheSameReactionTwiceIsIdempotent() throws Exception {
        Account me = account("멱등추가");
        long postId = newPost(me);

        react(me, postId, "help", true).andExpect(status().isOk());
        JsonNode again = body(react(me, postId, "help", true).andExpect(status().isOk()));

        assertThat(again.path("help").asInt())
                .as("""
                        2026-09 이전 계약은 POST .../reactions 하나가 토글이었다. 요청에 의도가 \
                        없어서 네트워크 재시도 한 번이 사용자의 반응을 조용히 되돌렸다.""")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("안 누른 반응을 취소해도 200 이다")
    void removingAReactionThatWasNeverThereIsIdempotent() throws Exception {
        Account me = account("멱등취소");
        long postId = newPost(me);

        JsonNode summary = body(react(me, postId, "empathy", false).andExpect(status().isOk()));

        assertThat(summary.path("empathy").asInt()).isZero();
        assertThat(summary.path("mine").size())
                .as("없던 것과 있던 것을 상태 코드로 나누면 앱이 두 갈래를 다뤄야 하는데 사용자에게는 결과가 같다")
                .isZero();
    }

    // ─────────────────────────── 검증 (완료 조건 6) ───────────────────────────

    @Test
    @DisplayName("board 값이 목록 밖이면 400 이고, 메시지가 가능한 값을 말해 준다")
    void rejectsAnUnknownBoard() throws Exception {
        Account me = account("잘못된보드");

        String body = createPost(me, """
                {"board":"건강병원","title":"제목","body":"본문"}
                """)
                .andExpect(status().isBadRequest())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        assertThat(body)
                .as("""
                        DB 에 CHECK 를 안 걸었고 계약에서만 값이 닫혀 있다 — 서비스가 유일한 \
                        방어선이다. 그냥 "잘못된 값" 이라고만 하면 부르는 쪽이 계약을 다시 열어 \
                        봐야 한다.""")
                .contains("walk_review");
    }

    @Test
    @DisplayName("반응 종류가 목록 밖이면 400 이다")
    void rejectsAnUnknownReactionType() throws Exception {
        Account me = account("잘못된반응");
        long postId = newPost(me);

        mockMvc.perform(post("/api/community/posts/" + postId + "/reactions/love")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("없는 글이면 404 다 — 상세·댓글·반응 셋 다")
    void missingPostIsNotFound() throws Exception {
        Account me = account("없는글");

        mockMvc.perform(get("/api/community/posts/999999")).andExpect(status().isNotFound());
        mockMvc.perform(get("/api/community/posts/999999/comments")).andExpect(status().isNotFound());
        mockMvc.perform(post("/api/community/posts/999999/reactions/help")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNotFound());
    }

    // ─────────────────────────── 커서 (완료 조건 8) ───────────────────────────

    @Test
    @DisplayName("커서가 장 경계에서 겹치지도 건너뛰지도 않는다")
    void cursorPagesWithoutOverlapOrGap() throws Exception {
        Account me = account("커서");
        for (int i = 0; i < 4; i++) {
            newPost(me);
        }

        JsonNode first = body(feed(me, "?limit=2").andExpect(status().isOk()));
        assertThat(first.path("items").size()).isEqualTo(2);
        assertThat(first.path("hasMore").asBoolean()).isTrue();

        JsonNode second = body(feed(me, "?limit=2&cursor=" + first.path("nextCursor").asText())
                .andExpect(status().isOk()));

        var seen = new HashSet<Long>();
        first.path("items").forEach(p -> seen.add(p.path("id").asLong()));
        second.path("items").forEach(p -> assertThat(seen.add(p.path("id").asLong()))
                .as("장 경계에서 같은 행이 두 번 나오면 안 된다")
                .isTrue());
        assertThat(seen).hasSize(4);
    }

    @Test
    @DisplayName("깨진 커서는 400 이 아니라 첫 장이다")
    void anUnreadableCursorGivesTheFirstPage() throws Exception {
        Account me = account("깨진커서");
        newPost(me);

        JsonNode firstPage = body(feed(me, "").andExpect(status().isOk()));
        JsonNode withBadCursor = body(feed(me, "?cursor=!!!not-base64!!!").andExpect(status().isOk()));

        assertThat(withBadCursor.path("items").get(0).path("id").asLong())
                .as("첫 장과 같은 것이 와야 한다 — 커서를 못 읽었으면 안 읽은 것처럼 군다")
                .isEqualTo(firstPage.path("items").get(0).path("id").asLong());
        assertThat(withBadCursor.path("items").size())
                .as("""
                        이슈 #170 의 완료 조건 8 은 "잘못된 커서는 400" 이라고 적었는데, 이 저장소는 \
                        이미 반대를 정했다(WalkCursor). 앱이 오래된 커서를 들고 있는 것은 흔한 \
                        일이고 거기서 오류를 내면 사용자는 목록을 아예 못 본다. 한 계약 안에서 \
                        같은 실패가 두 코드로 답하면 앱이 두 갈래를 다뤄야 한다.""")
                .isNotZero();
    }

    @Test
    @DisplayName("limit 은 거절하지 않고 자른다 — 0·음수는 기본값, 큰 값은 상한")
    void limitIsClampedNotRejected() throws Exception {
        Account me = account("리밋");
        newPost(me);

        feed(me, "?limit=0").andExpect(status().isOk());
        feed(me, "?limit=-5").andExpect(status().isOk());
        feed(me, "?limit=100000").andExpect(status().isOk());
    }

    // ─────────────────────────── 탈퇴자 (완료 조건 5) ───────────────────────────

    @Test
    @DisplayName("탈퇴한 사람의 글은 '알 수 없음' 으로 나오고, 남의 댓글은 그대로 산다")
    void aWithdrawnAuthorShowsAsUnknown() throws Exception {
        Account author = account("사라질사람");
        Account other = account("남는사람");
        long postId = body(createPost(author, """
                {"board":"free","title":"곧 탈퇴합니다","body":"안녕히"}
                """).andExpect(status().isCreated())).path("id").asLong();
        addComment(other, postId, "{\"body\":\"남의 댓글\"}").andExpect(status().isCreated());

        // 회원 탈퇴가 하는 일이 이것이다 — users 행 물리 삭제. FK 가 SET NULL 이라
        // 글은 남고 user_id 만 눕는다(#222).
        userRepository.deleteById(author.id());
        userRepository.flush();

        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/" + postId))
                .andExpect(status().isOk()));

        assertThat(detail.path("author").path("nickname").asText())
                .as("""
                        탈퇴 화면은 "복구할 수 없습니다" 라고 말하는데 커뮤니티에 닉네임이 계속 \
                        뜨면 안 된다(#82 가 social 에서 잡은 것과 같은 자리). 여기는 WithdrawnUsers \
                        조회가 필요 없다 — FK 가 SET NULL 이라 null 인 것이 곧 탈퇴다.""")
                .isEqualTo("알 수 없음");
        assertThat(detail.path("author").path("userId").asLong()).isZero();
        assertThat(detail.path("title").asText())
                .as("글 자체는 남아야 한다 — CASCADE 였다면 남의 댓글까지 사라진다")
                .isEqualTo("곧 탈퇴합니다");

        assertThat(body(mockMvc.perform(get("/api/community/posts/" + postId + "/comments"))
                .andExpect(status().isOk())).path("items").size())
                .as("남의 댓글은 살아 있어야 한다")
                .isEqualTo(1);
    }

    // ─────────────────────────── 필터 ───────────────────────────

    @Test
    @DisplayName("board 로 거르면 그 게시판만 온다. 빈 값은 전체다")
    void filtersByBoard() throws Exception {
        Account me = account("필터");
        long freePostId = body(createPost(me, "{\"board\":\"free\",\"title\":\"자유\",\"body\":\"b\"}")
                .andExpect(status().isCreated())).path("id").asLong();
        long bragPostId = body(createPost(me, "{\"board\":\"brag\",\"title\":\"자랑\",\"body\":\"b\"}")
                .andExpect(status().isCreated())).path("id").asLong();

        JsonNode brag = body(feed(me, "?board=brag"));
        brag.path("items").forEach(p -> assertThat(p.path("board").asText())
                .as("거른 게시판 밖의 글이 섞이면 필터가 아니다")
                .isEqualTo("brag"));

        JsonNode all = body(feed(me, "?board="));
        assertThat(idsOf(all))
                .as("앱이 칩을 껐을 때 빈 값을 보낸다 — 그것을 400 으로 만들면 전체 보기가 안 된다")
                .contains(freePostId, bragPostId);

        feed(me, "?board=없는게시판").andExpect(status().isBadRequest());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ResultActions createPost(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/community/posts")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions addComment(Account account, long postId, String json) throws Exception {
        return mockMvc.perform(post("/api/community/posts/" + postId + "/comments")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions react(Account account, long postId, String type, boolean on) throws Exception {
        String path = "/api/community/posts/" + postId + "/reactions/" + type;
        return mockMvc.perform((on ? post(path) : delete(path))
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions feed(Account account, String query) throws Exception {
        return mockMvc.perform(get("/api/community/posts" + query)
                .header("Authorization", "Bearer " + account.token()));
    }

    private long newPost(Account account) throws Exception {
        return body(createPost(account, "{\"board\":\"free\",\"title\":\"제목\",\"body\":\"본문\"}")
                .andExpect(status().isCreated()))
                .path("id").asLong();
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("community-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /**
     * 목록에서 <b>내가 만든 글</b>을 찾는다. 피드가 전역이라 {@code items.get(0)} 은 남의 것일
     * 수 있다 — 클래스 javadoc 참조.
     */
    private static JsonNode itemById(JsonNode page, long postId) {
        for (JsonNode item : page.path("items")) {
            if (item.path("id").asLong() == postId) {
                return item;
            }
        }
        throw new AssertionError("목록에 id=" + postId + " 이 없다. 첫 장 밖으로 밀렸는지 확인하라.");
    }

    private static java.util.List<Long> idsOf(JsonNode page) {
        java.util.List<Long> ids = new java.util.ArrayList<>();
        page.path("items").forEach(p -> ids.add(p.path("id").asLong()));
        return ids;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(StandardCharsets.UTF_8));
    }

    private record Account(long id, String token) { }
}
