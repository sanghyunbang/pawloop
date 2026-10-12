package com.heattrip.heat_trip_backend.community;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.community.dto.CommentRequest;
import com.heattrip.heat_trip_backend.community.dto.PostRequest;
import com.heattrip.heat_trip_backend.moderation.Blocks;
import com.heattrip.heat_trip_backend.moderation.Reports;
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
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.HashSet;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.within;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
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

    @Autowired
    private JdbcTemplate jdbc;

    @Autowired
    private Blocks blocks;

    // ─────────────────────────── 일곱 경로 ───────────────────────────

    /**
     * "이 장소의 글" — 이슈 #723. 글에 연결된 장소({@code contentId})로 목록을 좁힌다.
     *
     * <p>피드는 전역이라 크기를 세지 않는다(클래스 javadoc). 내가 만든 셋의 id 가 <b>들어 있는가 ·
     * 빠져 있는가</b>만 본다.
     */
    /** 장소 머리의 숫자 — 이슈 #729. 글 수만 여기서 잰다(산책 수는 {@code WalkIntegrationTest}). */
    @Test
    @DisplayName("장소 머리의 글 수는 그 장소를 골라 쓴 글만 세고, 모르는 장소는 0 이다 — 인증 없이도")
    void placeSummaryCountsPostsOfThatPlace() throws Exception {
        Account me = account("장소머리");
        String place = "summary-" + ACCOUNT_SEQUENCE.incrementAndGet();
        createPost(me, """
                {"board":"pet_place","title":"첫 글","body":"a","loc":"어느 곳","contentId":"%s"}
                """.formatted(place)).andExpect(status().isCreated());
        createPost(me, """
                {"board":"pet_place","title":"둘째 글","body":"b","loc":"어느 곳","contentId":"%s"}
                """.formatted(place)).andExpect(status().isCreated());
        createPost(me, """
                {"board":"free","title":"장소 없는 글","body":"c"}
                """).andExpect(status().isCreated());

        JsonNode summary = body(mockMvc.perform(get("/api/community/places/" + place + "/summary"))
                .andExpect(status().isOk()));
        assertThat(summary.path("posts").asLong()).isEqualTo(2);
        assertThat(summary.path("photos").asLong()).as("사진 없는 글 둘").isEqualTo(0);
        assertThat(summary.path("walks").asLong()).as("이 장소에서 한 산책은 없다").isEqualTo(0);

        JsonNode unknown = body(mockMvc.perform(get("/api/community/places/no-such-place/summary"))
                .andExpect(status().isOk()));
        assertThat(unknown.path("posts").asLong()).isEqualTo(0);
        assertThat(unknown.path("walks").asLong()).isEqualTo(0);
    }

    @Test
    @DisplayName("?contentId= 는 그 장소에 연결된 글만 준다 — 다른 장소 · 장소 없는 글은 빠진다")
    void feedFiltersByLinkedPlace() throws Exception {
        Account me = account("장소글");
        long here = body(createPost(me, """
                {"board":"pet_place","title":"성수연방 마당","body":"그늘이 좋아요",
                 "loc":"성수연방","contentId":"2745594"}
                """).andExpect(status().isCreated())).path("id").asLong();
        long elsewhere = body(createPost(me, """
                {"board":"pet_place","title":"서울숲 호수","body":"오리가 있어요",
                 "loc":"서울숲","contentId":"2733847"}
                """).andExpect(status().isCreated())).path("id").asLong();
        long nowhere = body(createPost(me, """
                {"board":"free","title":"장소 없는 글","body":"그냥 씁니다"}
                """).andExpect(status().isCreated())).path("id").asLong();

        java.util.List<Long> filtered = idsOf(body(feed(me, "?contentId=2745594").andExpect(status().isOk())));
        assertThat(filtered).contains(here);
        assertThat(filtered).doesNotContain(elsewhere, nowhere);

        assertThat(idsOf(body(feed(me, "?contentId=2745594&board=pet_place").andExpect(status().isOk()))))
                .as("다른 필터와 함께 쓸 수 있다")
                .contains(here)
                .doesNotContain(elsewhere, nowhere);

        assertThat(idsOf(body(feed(me, "?contentId=no-such-place").andExpect(status().isOk()))))
                .as("모르는 장소는 400 이 아니라 빈 장이다 — 글은 공개다")
                .doesNotContain(here, elsewhere, nowhere);

        assertThat(idsOf(body(feed(me, "?contentId=").andExpect(status().isOk()))))
                .as("빈 문자열은 필터가 없는 것과 같다")
                .contains(here, elsewhere, nowhere);
    }

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
        assertThat(afterRemove.path("mine").isArray())
                .as("""
                        size() == 0 은 null 에도 참이다 — 그 단언만으로는 "로그인했는데 안 \
                        눌렀다"([])와 "비인증"(null)이 구별되지 않는다. 앱은 그 둘을 다르게 \
                        그린다 — 꺼진 버튼과 누를 수 없는 상태다.""")
                .isTrue();

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

    // ─────────────────────────── 삭제 (#211) ───────────────────────────

    @Test
    @DisplayName("내 글을 지우면 댓글과 반응이 함께 사라진다 — 부모 없는 행을 남기지 않는다")
    void deletingMyPostTakesEverythingWithIt() throws Exception {
        Account me = account("글쓴이");
        Account other = account("댓글쓴이");
        long postId = newPost(me);

        addComment(other, postId, "{\"body\":\"남의 댓글\"}")
                .andExpect(status().isCreated());
        react(me, postId, "help", true).andExpect(status().isOk());

        mockMvc.perform(delete("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/community/posts/" + postId))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/community/posts/" + postId + "/comments"))
                .andExpect(status().isNotFound());
    }

    // ─────────────────── 신고 (#166) ───────────────────

    @Test
    @DisplayName("남의 글을 신고하면 접수 번호와 시각만 돌아온다 — 피신고자 id 는 안 준다")
    void reportingSomeoneElsesPostReturnsOnlyAReceipt() throws Exception {
        Account author = account("신고당함");
        Account reporter = account("신고함");
        long postId = newPost(author);

        JsonNode receipt = body(report(reporter, "/api/community/posts/" + postId + "/reports",
                "{\"reason\":\"spam\",\"memo\":\"광고예요\"}")
                .andExpect(status().isCreated()));

        assertThat(receipt.path("reportId").asLong()).isPositive();
        assertThat(receipt.path("createdAt").asText())
                .as("계약이 format: date-time 이라 오프셋이 붙어야 한다 (#209)")
                .endsWith("Z");
        assertThat(receipt.has("reportedUserId"))
                .as("""
                        신고자는 익명이고 피신고자에게는 알림이 안 간다. 응답에 무엇이 더 \
                        실리면 그것으로 남의 상태를 물어볼 수 있게 된다.""")
                .isFalse();
    }

    @Test
    @DisplayName("내가 쓴 글은 신고할 수 없다 — 신고 수를 부풀리는 자리다")
    void reportingMyOwnPostIsRejected() throws Exception {
        Account me = account("자기신고");
        long postId = newPost(me);

        report(me, "/api/community/posts/" + postId + "/reports", "{\"reason\":\"spam\"}")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("모르는 사유는 400 이다 — other 로 눕히면 운영자가 세는 숫자가 틀어진다")
    void unknownReasonIsRejected() throws Exception {
        Account author = account("사유주인");
        Account reporter = account("사유신고");
        long postId = newPost(author);

        report(reporter, "/api/community/posts/" + postId + "/reports", "{\"reason\":\"광고\"}")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("같은 글을 두 번 신고할 수 있다 — 글이 수정되기 때문이다")
    void thesameuserCanReportTheSamePostTwice() throws Exception {
        Account author = account("두번주인");
        Account reporter = account("두번신고");
        long postId = newPost(author);
        String path = "/api/community/posts/" + postId + "/reports";

        long first = body(report(reporter, path, "{\"reason\":\"spam\"}")
                .andExpect(status().isCreated())).path("reportId").asLong();
        long second = body(report(reporter, path, "{\"reason\":\"abuse\"}")
                .andExpect(status().isCreated())).path("reportId").asLong();

        assertThat(second)
                .as("""
                        막으면 작성자가 신고 뒤 본문을 더 나쁜 것으로 고쳤을 때 재신고가 안 되고 \
                        (#211 이 PATCH 를 열었다), 운영자에게 남는 기록은 고치기 전 본문뿐이다.""")
                .isNotEqualTo(first);
    }

    @Test
    @DisplayName("없는 글을 신고하면 404 다")
    void reportingAMissingPostIsNotFound() throws Exception {
        Account me = account("없는글신고");

        report(me, "/api/community/posts/999999/reports", "{\"reason\":\"spam\"}")
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("로그인 없이 신고하면 401 이다")
    void reportingWithoutAuthIsUnauthorized() throws Exception {
        Account author = account("비로그인주인");
        long postId = newPost(author);

        mockMvc.perform(post("/api/community/posts/" + postId + "/reports")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"spam\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("댓글 신고는 부모 글을 맥락으로 함께 벤다 — 댓글 한 줄만 남으면 판단이 안 된다")
    void reportingACommentSnapshotsTheParentPost() throws Exception {
        Account author = account("댓글주인");
        Account reporter = account("댓글신고");
        long postId = newPost(author);
        long commentId = body(addComment(author, postId, "{\"body\":\"신고당할 댓글\"}")
                .andExpect(status().isCreated())).path("id").asLong();

        long reportId = body(report(reporter,
                "/api/community/posts/" + postId + "/comments/" + commentId + "/reports",
                "{\"reason\":\"abuse\"}")
                .andExpect(status().isCreated())).path("reportId").asLong();

        assertThat(snapshotRoles(reportId))
                .as("""
                        글을 지우면 fk_comment_post 가 CASCADE 라 댓글이 함께 사라져 되짚을 수도 \
                        없다. 그래서 부모 글을 함께 벤다 — 채팅이 앞뒤 roomSeq 를 남긴 이유와 같다.""")
                .containsExactlyInAnyOrder("target", "context");
    }

    @Test
    @DisplayName("신고 사본이 제목과 본문을 벤다 — 원본을 지워도 남는다")
    void theSnapshotSurvivesDeletingTheOriginal() throws Exception {
        Account author = account("사본주인");
        Account reporter = account("사본신고");
        long postId = newPost(author);

        long reportId = body(report(reporter, "/api/community/posts/" + postId + "/reports",
                "{\"reason\":\"spam\"}").andExpect(status().isCreated()))
                .path("reportId").asLong();

        mockMvc.perform(delete("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + author.token()))
                .andExpect(status().isNoContent());

        assertThat(snapshotBodies(reportId))
                .as("참조만 남기면 작성자가 글을 지우는 순간 운영자가 판단할 것이 없다")
                .containsExactly("본문");
        assertThat(snapshotTitles(reportId))
                .as("제목에 욕설·광고가 실린 신고가 정확히 그 자리다")
                .containsExactly("제목");
    }

    @Test
    @DisplayName("긴 메모는 400 이 아니라 잘린다 — 거절하면 쓴 신고가 통째로 사라진다")
    void aLongMemoIsTruncated() throws Exception {
        Account author = account("메모주인");
        Account reporter = account("메모신고");
        long postId = newPost(author);

        String tooLong = "가".repeat(Reports.MAX_MEMO_LENGTH + 50);
        long reportId = body(report(reporter, "/api/community/posts/" + postId + "/reports",
                MAPPER.writeValueAsString(Map.of("reason", "spam", "memo", tooLong)))
                .andExpect(status().isCreated())).path("reportId").asLong();

        assertThat(memoOf(reportId)).hasSize(Reports.MAX_MEMO_LENGTH);
    }

    // ─────────────────── 차단 — 목록에서 뺀다 (애플 지침 1.2) ───────────────────
    //
    // 처음(#166)에는 빼지 않고 hiddenByBlock 만 붙였다. 1.2 가 "차단한 사람의 콘텐츠는 피드에서 즉시
    // 사라져야 한다" 고 요구해서 쿼리가 뺀다. 피드가 전역이라 목록 크기를 셀 수 없으므로(클래스 javadoc)
    // 여기서는 **이 검사만 쓰는 장소**로 좁혀서 센다 — 그 장소의 글은 이 검사가 만든 것뿐이다.

    @Test
    @DisplayName("차단한 사람의 글은 목록에 아예 안 온다 — 접어서 남기지 않는다(1.2)")
    void blockedAuthorsPostsAreLeftOutOfTheFeed() throws Exception {
        Account author = account("차단될사람");
        Account viewer = account("차단하는사람");
        String place = freshPlace();
        long blockedPost = newPostAt(author, place);
        long kept = newPostAt(viewer, place);

        blocks.block(viewer.id(), author.id());

        assertThat(idsOf(body(feed(viewer, "?contentId=" + place).andExpect(status().isOk()))))
                .as("""
                        차단한 사람의 글이 목록에 오면, 이미 깔린 앱은 '가린 사람의 글입니다 · 눌러서 보기' 로 \
                        그 자리를 남긴다 — 1.2 는 피드에서 사라지기를 요구한다.""")
                .containsExactly(kept);
        assertThat(idsOf(body(feed(viewer, "").andExpect(status().isOk()))))
                .as("장소로 좁히지 않은 피드도 같다 — 방금 쓴 글이라 첫 장 맨 위에 있었을 자리다")
                .doesNotContain(blockedPost)
                .contains(kept);
    }

    @Test
    @DisplayName("빼도 장은 꽉 찬다 — 쿼리에서 빼므로 둘을 달라면 둘이 오고, 커서도 안 어긋난다")
    void leavingOutKeepsPagesFull() throws Exception {
        Account blocked = account("섞인차단");
        Account neighbour = account("섞인이웃");
        Account viewer = account("섞인독자");
        String place = freshPlace();
        // 쓰인 순서: 이웃 · 차단 · 이웃 · 차단 · 이웃. 차단한 사람의 글이 장 경계마다 끼어 있다.
        long n1 = newPostAt(neighbour, place);
        newPostAt(blocked, place);
        long n2 = newPostAt(neighbour, place);
        newPostAt(blocked, place);
        long n3 = newPostAt(neighbour, place);
        blocks.block(viewer.id(), blocked.id());

        JsonNode first = body(mockMvc.perform(get("/api/community/posts")
                        .param("contentId", place).param("limit", "2")
                        .header("Authorization", "Bearer " + viewer.token()))
                .andExpect(status().isOk()));
        assertThat(idsOf(first))
                .as("응답을 만든 뒤 걸렀다면 이 장은 [n3] 하나였다 — 읽은 둘 중 하나가 차단한 사람의 글이다")
                .containsExactly(n3, n2);
        assertThat(first.path("hasMore").asBoolean()).isTrue();

        JsonNode second = body(mockMvc.perform(get("/api/community/posts")
                        .param("contentId", place).param("limit", "2")
                        .param("cursor", first.path("nextCursor").asText())
                        .header("Authorization", "Bearer " + viewer.token()))
                .andExpect(status().isOk()));
        assertThat(idsOf(second))
                .as("커서는 돌려준 마지막 줄에서 이어진다 — 건너뛰거나 겹치지 않는다")
                .containsExactly(n1);
        assertThat(second.path("hasMore").asBoolean()).isFalse();
    }

    @Test
    @DisplayName("차단은 보는 사람의 설정이다 — 남에게는 그 글이 그대로 보인다")
    void leavingOutIsPerViewer() throws Exception {
        Account author = account("안가려질사람");
        Account blocker = account("가린사람");
        Account other = account("남의눈");
        String place = freshPlace();
        long postId = newPostAt(author, place);

        blocks.block(blocker.id(), author.id());

        assertThat(idsOf(body(feed(blocker, "?contentId=" + place)))).doesNotContain(postId);
        assertThat(itemById(body(feed(other, "?contentId=" + place)), postId).path("hiddenByBlock").asBoolean())
                .as("차단한 것은 blocker 의 화면 설정이지 글의 속성이 아니다")
                .isFalse();
    }

    @Test
    @DisplayName("차단한 사람의 글을 직접 열면 글은 오고 hiddenByBlock 이 참이다 — 앱이 내용을 안 그린다")
    void theDetailOfABlockedAuthorsPostComesFlagged() throws Exception {
        Account author = account("상세차단될");
        Account viewer = account("상세차단하는");
        long postId = newPostAt(author, freshPlace());

        blocks.block(viewer.id(), author.id());

        JsonNode post = body(detail(viewer, postId).andExpect(status().isOk()));
        assertThat(post.path("hiddenByBlock").asBoolean())
                .as("""
                        링크·알림으로 직접 여는 길이 있다. 404 로 숨기면 '지워진 글' 과 구별이 안 되고, \
                        false 로 주면 앱이 본문을 그린다.""")
                .isTrue();
    }

    @Test
    @DisplayName("차단한 사람의 댓글도 목록에 안 오고 댓글 수에서도 빠진다 — 남에게는 그대로다")
    void blockedAuthorsCommentsAreLeftOutAndUncounted() throws Exception {
        Account writer = account("댓글글쓴이");
        Account troll = account("댓글차단될");
        Account viewer = account("댓글차단하는");
        Account other = account("댓글남의눈");
        String place = freshPlace();
        long postId = newPostAt(writer, place);
        addComment(troll, postId, "{\"body\":\"차단될 댓글\"}").andExpect(status().isCreated());
        addComment(other, postId, "{\"body\":\"남을 댓글\"}").andExpect(status().isCreated());

        blocks.block(viewer.id(), troll.id());

        JsonNode mine = body(comments(viewer, postId).andExpect(status().isOk()));
        assertThat(mine.path("items")).hasSize(1);
        assertThat(mine.path("items").get(0).path("body").asText()).isEqualTo("남을 댓글");
        assertThat(itemById(body(feed(viewer, "?contentId=" + place)), postId).path("commentCount").asInt())
                .as("목록에서 뺀 댓글을 수에 남기면 '댓글 2' 를 보고 들어가 하나만 보게 된다")
                .isEqualTo(1);
        assertThat(body(detail(viewer, postId)).path("commentCount").asInt())
                .as("상세의 댓글 수도 같은 규칙이다 — 카드와 상세가 다른 수를 말하면 안 된다")
                .isEqualTo(1);

        assertThat(body(comments(other, postId)).path("items"))
                .as("남에게는 둘 다 보인다")
                .hasSize(2);
        assertThat(body(detail(other, postId)).path("commentCount").asInt()).isEqualTo(2);
    }

    @Test
    @DisplayName("저장해 둔 글도 그 사람을 차단하면 저장한 글에서 빠지고, 차단을 풀면 돌아온다")
    void bookmarksLeaveOutBlockedAuthorsUntilUnblocked() throws Exception {
        Account author = account("저장차단될");
        Account viewer = account("저장차단하는");
        long postId = newPostAt(author, freshPlace());
        mockMvc.perform(post("/api/community/posts/" + postId + "/bookmark")
                        .header("Authorization", "Bearer " + viewer.token()))
                .andExpect(status().isOk());

        blocks.block(viewer.id(), author.id());
        assertThat(idsOf(body(savedPosts(viewer).andExpect(status().isOk()))))
                .as("저장한 글 화면도 커뮤니티 글 목록이다 — 거기만 남기면 차단한 사람의 사진이 그대로 보인다")
                .doesNotContain(postId);

        blocks.unblock(viewer.id(), author.id());
        assertThat(idsOf(body(savedPosts(viewer).andExpect(status().isOk()))))
                .as("저장 행은 지우지 않았다 — 차단을 풀면 다시 보인다")
                .contains(postId);
    }

    @Test
    @DisplayName("차단 목록이 있는 사람에게도 탈퇴한 사람의 글은 보인다 — not in 이 null 을 삼키지 않는다")
    void withdrawnAuthorsPostsSurviveTheExclusion() throws Exception {
        Account gone = account("곧떠날사람");
        Account someone = account("차단당한아무나");
        Account viewer = account("차단이있는독자");
        String place = freshPlace();
        long postId = newPostAt(gone, place);
        blocks.block(viewer.id(), someone.id());
        // 회원 탈퇴가 하는 일 — users 행 물리 삭제. FK 가 SET NULL 이라 post.user_id 가 비워진다.
        userRepository.deleteById(gone.id());

        assertThat(idsOf(body(feed(viewer, "?contentId=" + place))))
                .as("""
                        'u.id is null or' 가 없으면 not in 이 NULL 에 대해 unknown 이라, 차단을 하나라도 \
                        걸어 둔 사람에게는 탈퇴한 사람의 글이 전부 사라진다.""")
                .containsExactly(postId);
    }

    @Test
    @DisplayName("게스트에게는 아무것도 안 빠진다 — 차단한 사람이 없다")
    void guestsSeeEverything() throws Exception {
        Account author = account("게스트대상");
        Account blocker = account("게스트가리는");
        String place = freshPlace();
        long postId = newPostAt(author, place);
        blocks.block(blocker.id(), author.id());

        JsonNode item = itemById(
                body(mockMvc.perform(get("/api/community/posts").param("contentId", place))
                        .andExpect(status().isOk())),
                postId);
        assertThat(item.path("hiddenByBlock").asBoolean()).isFalse();
    }

    /** 이 검사 하나만 쓰는 장소 id. 피드가 전역이어도 이 장소로 좁히면 셀 수 있다. */
    private static String freshPlace() {
        return "block-%d-%d".formatted(System.nanoTime(), ACCOUNT_SEQUENCE.incrementAndGet());
    }

    private long newPostAt(Account account, String contentId) throws Exception {
        return body(createPost(account, """
                {"board":"free","title":"제목","body":"본문","contentId":"%s"}
                """.formatted(contentId)).andExpect(status().isCreated()))
                .path("id").asLong();
    }

    private ResultActions comments(Account account, long postId) throws Exception {
        return mockMvc.perform(get("/api/community/posts/" + postId + "/comments")
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions savedPosts(Account account) throws Exception {
        return mockMvc.perform(get("/api/community/bookmarks")
                .header("Authorization", "Bearer " + account.token()));
    }

    // ─────────────────── 글 수정 (#211) ───────────────────

    @Test
    @DisplayName("보낸 키만 바뀐다 — 제목만 보내면 본문이 그대로다")
    void patchChangesOnlyTheKeysSent() throws Exception {
        Account me = account("부분수정");
        long postId = newPost(me);

        JsonNode updated = body(patchPost(me, postId, "{\"title\":\"고친 제목\"}")
                .andExpect(status().isOk()));

        assertThat(updated.path("title").asText()).isEqualTo("고친 제목");
        assertThat(updated.path("body").asText())
                .as("""
                        PostInput 을 재사용하면 required 셋이라 본문을 다시 보내야 하고, 그 \
                        사이 다른 기기에서 고친 본문을 조용히 되돌린다 (ADR-0017 규약 4).""")
                .isEqualTo("본문");
        assertThat(updated.path("board").asText()).isEqualTo("free");
    }

    @Test
    @DisplayName("고치면 updatedAt 이 생긴다 — 그 전에는 null 이다")
    void patchStampsUpdatedAt() throws Exception {
        Account me = account("수정시각");
        long postId = newPost(me);

        assertThat(body(detail(me, postId).andExpect(status().isOk())).path("updatedAt").isNull())
                .as("한 번도 안 고친 글에 '수정됨' 이 붙으면 안 된다")
                .isTrue();

        String stamped = body(patchPost(me, postId, "{\"body\":\"고친 본문\"}")
                .andExpect(status().isOk()))
                .path("updatedAt").asText();

        assertThat(Instant.parse(stamped))
                .as("createdAt 과 같은 규약이다 — 오프셋을 갖고 나가야 앱이 지역 시각으로 안 읽는다")
                .isCloseTo(Instant.now(), within(2, ChronoUnit.MINUTES));
    }

    @Test
    @DisplayName("같은 값을 다시 보내면 updatedAt 이 안 생긴다 — 안 바뀐 글에 '수정됨' 은 거짓말이다")
    void patchWithTheSameValuesDoesNotStamp() throws Exception {
        Account me = account("같은값");
        long postId = newPost(me);

        JsonNode same = body(patchPost(me, postId, "{\"title\":\"제목\",\"body\":\"본문\"}")
                .andExpect(status().isOk()));

        assertThat(same.path("updatedAt").isNull()).isTrue();
    }

    @Test
    @DisplayName("board 를 바꾸면 글이 그 게시판으로 옮겨 간다 — 잘못 고른 게시판을 고치는 자리다")
    void patchMovesThePostBetweenBoards() throws Exception {
        Account me = account("게시판이동");
        long postId = newPost(me);

        patchPost(me, postId, "{\"board\":\"health\"}").andExpect(status().isOk());

        assertThat(idsOf(body(feed(me, "?board=health"))))
                .contains(postId);
        assertThat(idsOf(body(feed(me, "?board=free"))))
                .as("옮겼는데 원래 게시판에도 남아 있으면 한 글이 두 곳에서 읽힌다")
                .doesNotContain(postId);
    }

    @Test
    @DisplayName("고칠 것이 없으면 400 이다 — 아무 일도 안 하면서 200 이면 '고쳐졌다' 로 읽힌다")
    void patchWithNothingToChangeIsRejected() throws Exception {
        Account me = account("빈수정");
        long postId = newPost(me);

        patchPost(me, postId, "{}").andExpect(status().isBadRequest());
        patchPost(me, postId, "{\"title\":\"   \"}")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("없는 게시판으로는 못 옮긴다")
    void patchWithAnUnknownBoardIsRejected() throws Exception {
        Account me = account("없는게시판");
        long postId = newPost(me);

        patchPost(me, postId, "{\"board\":\"건강병원\"}")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("남의 글은 못 고친다 — 삭제와 같은 이유로 404 가 아니라 403 이다")
    void patchingSomeoneElsesPostIsForbidden() throws Exception {
        Account owner = account("수정주인");
        Account stranger = account("수정남");
        long postId = newPost(owner);

        patchPost(stranger, postId, "{\"title\":\"남이 고침\"}")
                .andExpect(status().isForbidden());

        assertThat(body(detail(owner, postId)).path("title").asText())
                .as("403 을 주고도 값이 바뀌었으면 그게 더 나쁘다")
                .isEqualTo("제목");
    }

    @Test
    @DisplayName("없는 글을 고치면 404 다")
    void patchingAMissingPostIsNotFound() throws Exception {
        Account me = account("없는글수정");

        patchPost(me, 999999, "{\"title\":\"x\"}").andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("본문 상한은 수정에도 걸린다 — 작성만 막으면 고치기로 우회된다")
    void patchEnforcesTheBodyLimit() throws Exception {
        Account me = account("수정상한");
        long postId = newPost(me);

        String tooLong = "가".repeat(PostRequest.MAX_BODY_LENGTH + 1);
        patchPost(me, postId, MAPPER.writeValueAsString(Map.of("body", tooLong)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("로그인 없이 고치면 401 이다")
    void patchingWithoutAuthIsUnauthorized() throws Exception {
        Account me = account("비로그인수정");
        long postId = newPost(me);

        mockMvc.perform(patch("/api/community/posts/" + postId)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"x\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("남의 글은 404 가 아니라 403 이다 — 글의 존재는 이미 공개다")
    void deletingSomeoneElsesPostIsForbidden() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");
        long postId = newPost(owner);

        mockMvc.perform(delete("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isForbidden());

        assertThat(itemById(body(feed(stranger, "").andExpect(status().isOk())), postId))
                .as("""
                        Dogs·Walks 는 남의 것을 404 로 숨기지만(ADR-0017 규약 3) 커뮤니티는 \
                        반대다 — 방금 목록에서 본 글을 삭제에서만 없다고 하면 아무것도 못 \
                        가리면서 사용자는 '지웠는데 안 사라졌다' 로 읽는다.""")
                .isNotNull();
    }

    @Test
    @DisplayName("없는 글을 지우면 404 다")
    void deletingAMissingPostIsNotFound() throws Exception {
        Account me = account("없는글삭제");

        mockMvc.perform(delete("/api/community/posts/999999")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("내 댓글만 지운다 — 글 주인이라도 남의 댓글은 못 지운다")
    void onlyTheCommentAuthorCanDeleteIt() throws Exception {
        Account owner = account("글주인");
        Account commenter = account("댓글주인");
        long postId = newPost(owner);

        long commentId = body(addComment(commenter, postId,
                "{\"body\":\"내 댓글\"}")
                .andExpect(status().isCreated())).path("id").asLong();

        // 글 주인이 남의 댓글을 지우려 한다. 관리(moderation)는 #166 이 갖는 결정이라
        // 여기서 미리 열지 않는다.
        mockMvc.perform(delete("/api/community/posts/" + postId + "/comments/" + commentId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isForbidden());

        mockMvc.perform(delete("/api/community/posts/" + postId + "/comments/" + commentId)
                        .header("Authorization", "Bearer " + commenter.token()))
                .andExpect(status().isNoContent());

        JsonNode page = body(mockMvc.perform(
                get("/api/community/posts/" + postId + "/comments")));
        assertThat(page.path("items").size()).isZero();
    }

    @Test
    @DisplayName("다른 글의 댓글 id 로 지우려 하면 404 다 — 권한 문제가 아니라 경로가 틀린 것이다")
    void deletingACommentUnderTheWrongPostIsNotFound() throws Exception {
        Account me = account("경로틀림");
        long mine = newPost(me);
        long another = newPost(me);

        long commentId = body(addComment(me, mine,
                "{\"body\":\"댓글\"}")
                .andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(delete("/api/community/posts/" + another + "/comments/" + commentId)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("탈퇴한 사람의 글은 아무도 못 지운다 — 주인 없는 글을 지우는 것은 관리다")
    void aWithdrawnAuthorsPostCannotBeDeletedByAnyone() throws Exception {
        Account gone = account("떠날사람");
        Account other = account("남은사람");
        long postId = newPost(gone);

        // 탈퇴하면 post.user_id 가 NULL 이 된다(ON DELETE SET NULL, ADR-0016 결정 5).
        userRepository.deleteById(gone.id());

        mockMvc.perform(delete("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + other.token()))
                .andExpect(status().isForbidden());

        assertThat(itemById(body(feed(other, "").andExpect(status().isOk())), postId)
                .path("author").path("userId").asInt())
                .as("글은 남아 있고 작성자만 알 수 없음이 된다")
                .isZero();
    }

    @Test
    @DisplayName("삭제는 로그인이 필요하다 — 게스트는 401 이다")
    void deletingRequiresAuthentication() throws Exception {
        Account me = account("게스트삭제");
        long postId = newPost(me);

        mockMvc.perform(delete("/api/community/posts/" + postId))
                .andExpect(status().isUnauthorized());
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
                        서비스가 첫 방어선이고, 사람에게 말해 주는 유일한 자리다. 그냥 "잘못된 값" \
                        이라고만 하면 부르는 쪽이 계약을 다시 열어 봐야 한다.
                        뒤에는 DB 의 chk_post_board 가 있다(#167) — 그건 서비스를 안 지나는 길을 \
                        막을 뿐 메시지를 만들어 주지는 않는다.""")
                .contains("walk_review");
    }

    @Test
    @DisplayName("긴 닉네임을 가진 사람도 글과 댓글을 쓸 수 있다 — handle 이 users.nickname 보다 좁으면 안 된다")
    void aLongNicknameDoesNotWedgeWriting() throws Exception {
        // users.nickname 은 VARCHAR(255) 인데 post.handle 을 50 으로 세웠던 적이 있다(#169).
        // 그러면 51자 닉네임을 가진 사람의 **모든** 글·댓글 작성이 영구히 500 이 된다 —
        // MySQL 8 의 STRICT_TRANS_TABLES 는 자르지 않고 ERROR 1406 으로 거절한다.
        // 읽기와 반응은 되는데 쓰기만 죽어서, 사용자도 로그도 이유를 못 말한다.
        Account me = account("가".repeat(200));

        long postId = newPost(me);

        mockMvc.perform(post("/api/community/posts/" + postId + "/comments")
                        .header("Authorization", "Bearer " + me.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"body":"긴 닉네임으로 다는 댓글"}
                                """))
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("createdAt 이 오프셋을 달고 나간다 — 계약이 format: date-time 이라고 선언했다")
    void createdAtCarriesAnOffset() throws Exception {
        Account me = account("시각");

        JsonNode created = body(createPost(me, """
                {"board":"free","title":"제목","body":"본문"}
                """).andExpect(status().isCreated()));
        String createdAt = created.path("createdAt").asText();

        assertThat(createdAt)
                .as("""
                        LocalDateTime 은 Jackson 이 오프셋 없이 직렬화한다. 계약은 \
                        format: date-time 이라고 선언해 뒀는데 그건 오프셋이 있어야 성립하는 \
                        형식이고, 앱의 DateTime.tryParse 는 오프셋 없는 문자열을 **기기 지역 \
                        시각**으로 읽는다 — 서버와 기기의 시간대가 다르면 그만큼 어긋난 시각이 \
                        그려진다. WalkResponse 가 같은 이유로 Instant 다.""")
                .endsWith("Z");

        assertThat(Instant.parse(createdAt))
                .as("값 자체도 지금이어야 한다 — 시간대를 안 붙였을 뿐 아니라 9시간 어긋나 있으면 안 된다")
                .isCloseTo(Instant.now(), within(2, ChronoUnit.MINUTES));
    }

    @Test
    @DisplayName("같은 반응을 동시에 두 번 눌러도 200 이다 — 예외를 삼키는 것으로는 멱등이 안 된다")
    void concurrentReactionsStayIdempotent() throws Exception {
        Account me = account("동시반응");
        long postId = newPost(me);

        // 선조회를 지나 둘 다 INSERT 를 시도하게 만든다. 예전 구현은 여기서 한 쪽이
        // DataIntegrityViolationException 을 맞고, 그것을 잡아도 트랜잭션이 이미
        // rollback-only 라 500 이 나갔다.
        int threads = 8;
        ExecutorService pool = Executors.newFixedThreadPool(threads);
        CountDownLatch start = new CountDownLatch(1);
        List<Future<Integer>> futures = new ArrayList<>();
        for (int i = 0; i < threads; i++) {
            futures.add(pool.submit(() -> {
                start.await();
                return mockMvc.perform(post("/api/community/posts/" + postId + "/reactions/help")
                                .header("Authorization", "Bearer " + me.token()))
                        .andReturn().getResponse().getStatus();
            }));
        }
        start.countDown();

        List<Integer> statuses = new ArrayList<>();
        for (Future<Integer> f : futures) {
            statuses.add(f.get(30, TimeUnit.SECONDS));
        }
        pool.shutdown();

        assertThat(statuses)
                .as("한 번이라도 500 이면 '이미 눌렀어도 200' 이라는 약속이 동시 요청에서 거짓이다")
                .containsOnly(200);

        JsonNode detail = body(mockMvc.perform(
                get("/api/community/posts/" + postId)
                        .header("Authorization", "Bearer " + me.token())));
        assertThat(detail.path("reactions").path("help").asInt())
                .as("멱등이면 여덟 번 눌러도 하나다")
                .isEqualTo(1);

        // 취소도 같다 — 조회 후 삭제였을 때는 진 쪽이 StaleStateException 으로 500 이었다.
        ExecutorService pool2 = Executors.newFixedThreadPool(threads);
        CountDownLatch start2 = new CountDownLatch(1);
        List<Future<Integer>> off = new ArrayList<>();
        for (int i = 0; i < threads; i++) {
            off.add(pool2.submit(() -> {
                start2.await();
                return mockMvc.perform(delete("/api/community/posts/" + postId + "/reactions/help")
                                .header("Authorization", "Bearer " + me.token()))
                        .andReturn().getResponse().getStatus();
            }));
        }
        start2.countDown();
        List<Integer> offStatuses = new ArrayList<>();
        for (Future<Integer> f : off) {
            offStatuses.add(f.get(30, TimeUnit.SECONDS));
        }
        pool2.shutdown();

        assertThat(offStatuses).containsOnly(200);
    }

    @Test
    @DisplayName("본문이 상한을 넘으면 400 이다 — TEXT 컬럼이라 안 막으면 65535바이트까지 들어간다")
    void rejectsABodyOverTheLimit() throws Exception {
        Account me = account("긴본문");

        createPost(me, """
                {"board":"free","title":"제목","body":"%s"}
                """.formatted("가".repeat(PostRequest.MAX_BODY_LENGTH + 1)))
                .andExpect(status().isBadRequest());

        createPost(me, """
                {"board":"free","title":"제목","body":"%s"}
                """.formatted("가".repeat(PostRequest.MAX_BODY_LENGTH)))
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("댓글도 상한이 있고 글보다 짧다")
    void rejectsACommentOverTheLimit() throws Exception {
        Account me = account("긴댓글");
        long postId = newPost(me);

        assertThat(CommentRequest.MAX_BODY_LENGTH)
                .as("댓글은 스레드에서 다른 댓글들과 함께 읽힌다 — 한 줄이 화면을 다 먹으면 스레드가 아니다")
                .isLessThan(PostRequest.MAX_BODY_LENGTH);

        mockMvc.perform(post("/api/community/posts/" + postId + "/comments")
                        .header("Authorization", "Bearer " + me.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"body":"%s"}
                                """.formatted("가".repeat(CommentRequest.MAX_BODY_LENGTH + 1))))
                .andExpect(status().isBadRequest());
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

    private ResultActions report(Account account, String path, String json) throws Exception {
        return mockMvc.perform(post(path)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    /**
     * 신고 사본의 {@code role} 들.
     *
     * <p><b>JDBC 로 직접 읽는다.</b> 신고를 읽는 API 가 아직 없고, 만들려면 관리자 인가를
     * 함께 정해야 한다(#166 이 다음 조각으로 갖고 있다). 그 결정을 테스트가 앞질러 끌고 오지
     * 않는다.
     */
    private List<String> snapshotRoles(long reportId) {
        return jdbc.queryForList(
                "select role from report_snapshot where report_id = ?", String.class, reportId);
    }

    private List<String> snapshotBodies(long reportId) {
        return jdbc.queryForList(
                "select body from report_snapshot where report_id = ? and role = 'target'",
                String.class, reportId);
    }

    private List<String> snapshotTitles(long reportId) {
        return jdbc.queryForList(
                "select title from report_snapshot where report_id = ? and role = 'target'",
                String.class, reportId);
    }

    private String memoOf(long reportId) {
        return jdbc.queryForObject("select memo from report where id = ?", String.class, reportId);
    }

    private ResultActions patchPost(Account account, long postId, String json) throws Exception {
        return mockMvc.perform(patch("/api/community/posts/" + postId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions detail(Account account, long postId) throws Exception {
        return mockMvc.perform(get("/api/community/posts/" + postId)
                .header("Authorization", "Bearer " + account.token()));
    }

    // ─────────────────── 우리 동네 (#342) ───────────────────

    @Test
    @DisplayName("우리 동네 토글이 같은 구의 글만 준다 — 다른 구도, 동네를 안 고른 사람도 빠진다")
    void neighborhoodFilterKeepsOnlyTheSameDistrict() throws Exception {
        Account me = accountInSeongdong("성동사람");
        Account neighbour = accountInSeongdong("성동이웃");
        Account faraway = accountIn("종로사람", "1111051500");
        Account nowhere = account("동네없는사람");

        long mine = newPost(me);
        long neighbours = newPost(neighbour);
        long far = newPost(faraway);
        long none = newPost(nowhere);

        java.util.List<Long> ids = idsOf(body(
                feed(me, "?neighborhood=mine").andExpect(status().isOk())));

        assertThat(ids).contains(mine, neighbours);
        assertThat(ids)
                .as("다른 구의 글이 '우리 동네' 에 섞이면 그 토글이 뜻을 잃는다")
                .doesNotContain(far);
        assertThat(ids)
                .as("동네를 안 고른 사람의 글은 어느 동네에도 속하지 않는다")
                .doesNotContain(none);
    }

    @Test
    @DisplayName("글 카드의 동네 표시가 구 단위다 — 동은 안 보인다")
    void thePostCardShowsTheDistrictOnly() throws Exception {
        Account me = accountInSeongdong("성동사람");
        long postId = newPost(me);

        JsonNode item = itemById(body(feed(me, "").andExpect(status().isOk())), postId);

        assertThat(item.path("authorDistrict").asText()).isEqualTo("성동구");
        assertThat(item.toString())
                .as("남의 사는 곳을 구보다 좁히면 그것만으로 사람을 찾아갈 수 있다")
                .doesNotContain("왕십리");
    }

    @Test
    @DisplayName("동네를 안 고른 사람의 글은 authorDistrict 가 null 이다")
    void withoutANeighborhoodTheDistrictIsNull() throws Exception {
        Account me = account("동네없는사람");
        long postId = newPost(me);

        JsonNode item = itemById(body(feed(me, "")), postId);

        assertThat(item.path("authorDistrict").isNull()).isTrue();
    }

    @Test
    @DisplayName("동네를 안 골랐는데 우리 동네를 부르면 400 이다 — 조용히 전국을 주지 않는다")
    void askingForMyNeighborhoodWithoutOneIs400() throws Exception {
        Account me = account("동네없는사람");

        feed(me, "?neighborhood=mine")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("mine 이 아닌 값은 400 — 구 코드를 직접 받지 않는다")
    void anArbitraryDistrictCodeIsRejected() throws Exception {
        Account me = accountInSeongdong("성동사람");

        feed(me, "?neighborhood=11110").andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("파라미터가 없으면 전국이다 — 기본이 바뀌면 안 된다")
    void withoutTheParameterTheFeedIsNationwide() throws Exception {
        Account me = accountInSeongdong("성동사람");
        Account faraway = accountIn("종로사람", "1111051500");
        long far = newPost(faraway);

        assertThat(idsOf(body(feed(me, "").andExpect(status().isOk())))).contains(far);
    }

    private long newPost(Account account) throws Exception {
        return body(createPost(account, "{\"board\":\"free\",\"title\":\"제목\",\"body\":\"본문\"}")
                .andExpect(status().isCreated()))
                .path("id").asLong();
    }

    /** 성동구 왕십리2동 사람. 앞 다섯 자리 11200 이 성동구다. */
    private Account accountInSeongdong(String nickname) {
        return accountIn(nickname, "1120052000");
    }

    /** 동네를 고른 사람. 코드는 서비스가 하는 것과 같은 경로로 저장한다. */
    private Account accountIn(String nickname, String neighborhoodCode) {
        Account created = account(nickname);
        User user = userRepository.findById(created.id()).orElseThrow();
        user.setNeighborhoodCode(neighborhoodCode);
        userRepository.save(user);
        return created;
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("community-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
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
