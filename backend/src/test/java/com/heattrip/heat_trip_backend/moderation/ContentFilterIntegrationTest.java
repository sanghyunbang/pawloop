package com.heattrip.heat_trip_backend.moderation;

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

import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 거르기가 <b>실제 경로 위에</b> 서 있는지 — 이슈 #681, 애플 App Review Guideline 1.2.
 *
 * <h2>왜 단위 테스트로 끝내지 않는가</h2>
 * <p>{@code ContentFilterTest} 는 판정만 잰다. 그것만 있으면 {@link ContentFilter} 를 아무도
 * 안 불러도 초록이다 — 이 저장소가 이미 겪은 모양이다({@code ChatMessages} javadoc 의
 * "해석기가 응답 경로 위에 서야 한다"). 그래서 여기서는 글·댓글·수정·말풍선을 <b>HTTP 로</b>
 * 지나간다.
 *
 * <p>애너테이션이 두 줄뿐인 것은 의도다 — {@code CommunityIntegrationTest} 와 글자 그대로
 * 같아야 스프링 컨텍스트 캐시를 공유한다(#21).
 */
@SpringBootTest(properties = {
        // **자바 소스에 적는다.** application-test.properties 에 적으면 ISO-8859-1 로
        // 읽혀 한글이 조용히 깨진다 — 아무것도 안 걸리는데 에러도 안 난다 (#789).
        //
        // 지어낸 낱말이다. 운영 목록과 상관이 없다 — 검사가 운영 데이터를 붙들고 있으면
        // 운영에서 낱말 하나를 빼는 날 검사가 깨진다.
        "app.moderation.banned-words=가짜욕,가짜혐오",
        // 허용 낱말은 금칙어를 통째로 품고 있어야 그 장치를 재는 뜻이 있다.
        "app.moderation.safe-words=가짜욕역,가짜욕점"
})
@AutoConfigureMockMvc
class ContentFilterIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong SEQUENCE = new AtomicLong();

    /** 검사 대상으로 쓰는 욕설 하나. 어디에 넣어도 같은 판정이어야 한다. */
    /**
     * 지어낸 금칙어 — 이슈 #789. 운영 목록과 상관이 없고,
     * {@code application-test.properties} 가 이 낱말을 주입한다.
     */
    private static final String DIRTY = "가짜욕 진짜 가짜혐오네";

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private ChatRoomService chatRooms;
    @Autowired private BannedWords bannedWords;

    /**
     * 설정에서 온 낱말이 <b>글자 그대로</b> 도착했는가.
     *
     * <p>이 검사가 없으면 글자가 깨져도 아무도 모른다. 2026-10-22 에 검사용 목록을
     * {@code application-test.properties} 에 적었다가 겪었다 — {@code .properties} 는
     * 자바 규약상 ISO-8859-1 로 읽혀서 한글이 {@code ê°ì§ì} 처럼 들어왔다.
     *
     * <p><b>에러도 로그도 안 났다.</b> 목록 개수는 맞게 세어졌고("금칙어 2개"), 다만
     * 글자가 달라 아무것도 안 걸렸다. 아래 HTTP 검사들이 400 대신 201 을 받고서야 알았다.
     * 운영에서 같은 일이 나면 <b>필터가 있는 척만 하는 채로</b> 돌아간다.
     */
    @Test
    @DisplayName("목록이 설정에서 글자 그대로 들어온다 — 깨져도 에러가 안 나는 종류다")
    void theListArrivesIntact() {
        assertThat(bannedWords.matches("가짜욕"))
                .as("설정에 넣은 금칙어가 안 걸린다 — 글자가 깨져서 들어왔을 것이다")
                .isTrue();
        assertThat(bannedWords.matches("가짜욕역"))
                .as("허용 낱말이 먼저 안 지워졌다 — 평범한 낱말을 쓴 사람이 막힌다")
                .isFalse();
    }


    // ─────────────────────────── 커뮤니티 ───────────────────────────

    @Test
    @DisplayName("글 — 본문에 금칙어가 있으면 400 이고, 제목에 있어도 400 이다")
    void postsAreFiltered() throws Exception {
        Account me = account("글쓴이");

        createPost(me, """
                {"board":"free","title":"오늘 산책","body":"%s"}
                """.formatted(DIRTY)).andExpect(status().isBadRequest());

        createPost(me, """
                {"board":"free","title":"%s","body":"오늘 산책 좋았어요"}
                """.formatted(DIRTY)).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("글 — 평범한 글은 그대로 201 이다. 과차단이 더 나쁜 버그다")
    void ordinaryPostsStillGoThrough() throws Exception {
        Account me = account("평범한사람");

        JsonNode created = body(createPost(me, """
                {"board":"free","title":"우리 개가 새끼를 낳았어요",
                 "body":"새벽에 개소리가 커서 깼는데 미친 듯이 뛰어놀아요. 가짜욕점에서 만나요"}
                """).andExpect(status().isCreated()));

        assertThat(created.path("id").asLong())
                .as("""
                        금칙어처럼 보이지만 평범한 낱말들이다 — BannedWords javadoc 이 왜 뺐는지 \
                        적어 뒀다. "가짜욕점" 은 허용 낱말이라 먼저 지워진다.""")
                .isPositive();
    }

    @Test
    @DisplayName("댓글 — 금칙어가 있으면 400, 평범하면 201")
    void commentsAreFiltered() throws Exception {
        Account me = account("댓글러");
        long postId = body(createPost(me, """
                {"board":"free","title":"댓글 받을 글","body":"아무 말이나 남겨 주세요"}
                """).andExpect(status().isCreated())).path("id").asLong();

        addComment(me, postId, "{\"body\":\"" + DIRTY + "\"}").andExpect(status().isBadRequest());
        addComment(me, postId, "{\"body\":\"저도 자주 가요\"}").andExpect(status().isCreated());
    }

    @Test
    @DisplayName("수정도 게시다 — 깨끗한 글을 올린 뒤 고쳐 넣으면 400 이고, 저장된 본문은 그대로다")
    void editingCannotSneakPastTheFilter() throws Exception {
        Account me = account("고치는사람");
        long postId = body(createPost(me, """
                {"board":"free","title":"처음엔 깨끗한 글","body":"한강 다녀왔습니다"}
                """).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(patch("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + me.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"body\":\"" + DIRTY + "\"}"))
                .andExpect(status().isBadRequest());

        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
        assertThat(detail.path("body").asText())
                .as("거절이면 아무것도 안 바뀌어야 한다 — 반쯤 저장되면 그게 더 나쁘다")
                .isEqualTo("한강 다녀왔습니다");
    }

    // ─────────────────────────── 채팅 ───────────────────────────

    @Test
    @DisplayName("말풍선 — 금칙어면 400 이고 번호도 안 태운다. 그 다음 평범한 말이 roomSeq 1 이다")
    void chatMessagesAreFiltered() throws Exception {
        Account me = account("채팅하는사람");
        long roomId = room(me);

        sendMessage(me, roomId, "{\"body\":\"" + DIRTY + "\"}").andExpect(status().isBadRequest());

        JsonNode sent = body(sendMessage(me, roomId, "{\"body\":\"안녕하세요 오늘 산책 가요\"}")
                .andExpect(status().isCreated()));

        assertThat(sent.path("roomSeq").asLong())
                .as("거절은 INSERT 전에 난다 — 번호를 태웠으면 여기가 2 다")
                .isEqualTo(1L);
    }

    // ─────────────────── 무엇이 걸렸는지 안 알려 준다 ───────────────────

    @Test
    @DisplayName("거절 본문이 걸린 낱말도 원문도 안 싣는다 — 알려 주면 우회법을 알려 주는 셈이다")
    void theRejectionBodyNamesNothing() throws Exception {
        Account me = account("막힌사람");

        JsonNode error = body(createPost(me, """
                {"board":"free","title":"제목","body":"%s"}
                """.formatted(DIRTY)).andExpect(status().isBadRequest())).path("error");

        assertThat(error.path("message").asText())
                .isEqualTo(ContentFilter.REJECTION_MESSAGE)
                .doesNotContain("가짜욕", "가짜혐오", "진짜");
        assertThat(error.path("code").asText())
                .as("""
                        400 이 늘 쓰는 그 코드다(GlobalExceptionHandler.codeOf) — 금칙어 전용 코드를
                        새로 만들면 그 코드 자체가 '금칙어에 걸렸다' 는 신호가 된다""")
                .isEqualTo("VALIDATION");
    }

    // ─────────────────────────── 도우미 ───────────────────────────

    private ResultActions createPost(Account me, String json) throws Exception {
        return mockMvc.perform(post("/api/community/posts")
                .header("Authorization", "Bearer " + me.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions addComment(Account me, long postId, String json) throws Exception {
        return mockMvc.perform(post("/api/community/posts/" + postId + "/comments")
                .header("Authorization", "Bearer " + me.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions sendMessage(Account me, long roomId, String json) throws Exception {
        return mockMvc.perform(post("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + me.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private long room(Account owner) {
        long serial = SEQUENCE.incrementAndGet();
        ChatRoomView room = chatRooms.openRoom(
                "CONTENT_FILTER_TEST", String.valueOf(serial), "방-%d".formatted(serial),
                "테스트", owner.id());
        return room.id();
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(StandardCharsets.UTF_8));
    }

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("filter681-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }
}
