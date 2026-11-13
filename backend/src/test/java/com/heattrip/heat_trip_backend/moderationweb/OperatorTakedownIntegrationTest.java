package com.heattrip.heat_trip_backend.moderationweb;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.moderation.ReportReason;
import com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 신고된 글·댓글을 운영자가 지운다 — 이슈 #718 둘째 조각.
 *
 * <h2>무엇을 지키나</h2>
 * <ol>
 *   <li><b>작성자가 지울 때와 같은 결과</b> — 댓글·반응·저장은 FK 로, 사진은 행을 거두고 파일을 커밋 뒤에 지운다.
 *       작성자 삭제가 사진을 떼고 운영자 삭제가 안 떼면, 지운 글의 사진이 S3 에 남는다.</li>
 *   <li><b>지우기 직전의 글이 기록에 남는다</b> — 신고 사본은 신고한 때의 글이다. 그 뒤에 고친 글을 지웠다면
 *       무엇을 지웠는지는 조치 기록만 안다. 그래서 신고 뒤에 고친 글로 잰다.</li>
 *   <li><b>한 신고에 판단은 한 번</b>, 채팅은 아직 지우지 않는다, 잘못된 요청은 아무것도 안 쓴다.</li>
 *   <li><b>본 입구로는 어떤 토큰으로도 안 지워진다</b> — 403 이고 글이 그대로다.</li>
 * </ol>
 *
 * <p>글은 진짜 경로(커뮤니티 API)로 만들고 신고한다 — 사본이 어떻게 만들어지는지까지 운영과 같게.
 */
class OperatorTakedownIntegrationTest extends AbstractOperatorIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String ACTOR = "ops-test";

    @Autowired private JdbcTemplate jdbc;
    @Autowired private Reports reports;

    @Test
    @DisplayName("신고된 글을 지우면 댓글·반응·저장·사진이 함께 사라지고, 신고 뒤에 고친 마지막 글이 기록에 남는다")
    void removingAPostErasesItAndKeepsTheLastCopy() throws Exception {
        User author = user("쓴 사람");
        User reader = user("읽는 사람");
        long postId = newPost(author, "신고될 글", "처음 본문");
        comment(reader, postId, "달린 댓글");
        mockMvc.perform(post("/api/community/posts/{id}/reactions/cute", postId).header("Authorization", bearer(reader)))
                .andExpect(status().isOk());
        mockMvc.perform(post("/api/community/posts/{id}/bookmark", postId).header("Authorization", bearer(reader)))
                .andExpect(status().isOk());
        String mediaKey = attachPhoto(author, postId);
        long reportId = reportPost(reader, postId);
        // 신고 뒤에 작성자가 고쳤다 — 신고 사본은 "처음 본문", 지우는 순간의 글은 "고친 본문" 이다.
        mockMvc.perform(patch("/api/community/posts/{id}", postId)
                        .header("Authorization", bearer(author))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"body\":\"고친 본문\"}"))
                .andExpect(status().isOk());

        JsonNode result = body(resolve(reportId, "remove", "욕설 반복").andExpect(status().isOk()));

        assertThat(result.path("decision").asText()).isEqualTo("remove");
        assertThat(targets(result.path("removed"))).containsExactly("community_post:" + postId);
        assertThat(targets(result.path("alreadyGone"))).isEmpty();
        assertThat(result.path("actionIds")).hasSize(1);

        mockMvc.perform(get("/api/community/posts/{id}", postId).header("Authorization", bearer(reader)))
                .andExpect(status().isNotFound());
        assertThat(count("SELECT COUNT(*) FROM post WHERE id = ?", postId)).isZero();
        assertThat(count("SELECT COUNT(*) FROM comment WHERE post_id = ?", postId))
                .as("댓글은 FK 의 CASCADE 로 함께 사라진다").isZero();
        assertThat(count("SELECT COUNT(*) FROM reaction WHERE post_id = ?", postId)).isZero();
        assertThat(count("SELECT COUNT(*) FROM post_bookmark WHERE post_id = ?", postId)).isZero();
        assertThat(count("SELECT COUNT(*) FROM media_objects WHERE ref_type = 'POST' AND ref_id = ?",
                String.valueOf(postId)))
                .as("사진 행은 FK 가 없어 CASCADE 로 안 지워진다 — 작성자 삭제와 같은 길로 거둬야 한다").isZero();
        verify(storage).deleteAll(argThat(keys -> keys.contains(mediaKey)));

        Map<String, Object> action = jdbc.queryForMap("SELECT * FROM moderation_action WHERE report_id = ?", reportId);
        assertThat(action.get("kind")).isEqualTo("remove");
        assertThat(((Number) action.get("subject_user_id")).longValue()).isEqualTo(author.getId());
        assertThat(action.get("target_type")).isEqualTo("community_post");
        assertThat(((Number) action.get("target_id")).longValue()).isEqualTo(postId);
        assertThat(action.get("author_name")).isEqualTo("쓴 사람");
        assertThat(action.get("title")).isEqualTo("신고될 글");
        assertThat(action.get("body"))
                .as("신고 사본은 신고한 때의 글이다. 지운 것은 고친 뒤의 글이고, 그것을 아는 곳은 여기뿐이다")
                .isEqualTo("고친 본문");
        assertThat(action.get("occurred_at")).isNotNull();
        assertThat(action.get("reason")).isEqualTo("욕설 반복");
        assertThat(action.get("actor")).isEqualTo(ACTOR);
        assertThat(action.get("created_at")).isNotNull();

        // 신고와 그 사본은 남는다 — 운영자는 지운 뒤에도 무엇이 신고됐는지 본다.
        mockMvc.perform(onOperatorConnector(get("/internal/moderation/reports/{id}", reportId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.targets[0].body").value("처음 본문"));
    }

    @Test
    @DisplayName("신고된 댓글을 지우면 그 댓글만 사라진다 — 맥락으로 함께 저장된 글은 그대로다")
    void removingACommentKeepsThePost() throws Exception {
        User author = user("글쓴이");
        User commenter = user("댓글 쓴 사람");
        User reporter = user("댓글 신고한 사람");
        long postId = newPost(author, "멀쩡한 글", "멀쩡한 본문");
        long kept = comment(reporter, postId, "남을 댓글");
        long commentId = comment(commenter, postId, "문제의 댓글");
        long reportId = body(mockMvc.perform(post("/api/community/posts/{p}/comments/{c}/reports", postId, commentId)
                        .header("Authorization", bearer(reporter))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"abuse\"}"))
                .andExpect(status().isCreated())).path("reportId").asLong();

        JsonNode result = body(resolve(reportId, "remove", "댓글 욕설").andExpect(status().isOk()));

        assertThat(targets(result.path("removed"))).containsExactly("community_comment:" + commentId);
        mockMvc.perform(get("/api/community/posts/{id}", postId).header("Authorization", bearer(reporter)))
                .andExpect(status().isOk());
        assertThat(count("SELECT COUNT(*) FROM comment WHERE id = ?", commentId)).isZero();
        assertThat(count("SELECT COUNT(*) FROM comment WHERE id = ?", kept)).isOne();

        Map<String, Object> action = jdbc.queryForMap("SELECT * FROM moderation_action WHERE report_id = ?", reportId);
        assertThat(action.get("target_type")).isEqualTo("community_comment");
        assertThat(((Number) action.get("target_id")).longValue()).isEqualTo(commentId);
        assertThat(((Number) action.get("subject_user_id")).longValue()).isEqualTo(commenter.getId());
        assertThat(action.get("title")).as("댓글에는 제목이 없다").isNull();
        assertThat(action.get("body")).isEqualTo("문제의 댓글");
        verify(storage, never()).deleteAll(any());
    }

    @Test
    @DisplayName("탈퇴한 사람의 글도 지운다 — 기록의 작성자 칸은 비어 있다")
    void removingAWithdrawnAuthorsPost() throws Exception {
        User author = user("떠난 사람");
        User reporter = user("남은 사람");
        long postId = newPost(author, "주인 없는 글", "주인 없는 본문");
        long reportId = reportPost(reporter, postId);
        mockMvc.perform(delete("/auth/me").header("Authorization", bearer(author)))
                .andExpect(status().isNoContent());
        assertThat(count("SELECT COUNT(*) FROM post WHERE id = ? AND user_id IS NULL", postId))
                .as("전제: 탈퇴해도 글은 남고 작성자 칸만 빈다").isOne();

        body(resolve(reportId, "remove", "탈퇴 전 올린 광고").andExpect(status().isOk()));

        Map<String, Object> action = jdbc.queryForMap("SELECT * FROM moderation_action WHERE report_id = ?", reportId);
        assertThat(action.get("subject_user_id")).isNull();
        assertThat(action.get("author_name")).isNull();
        assertThat(action.get("body")).isEqualTo("주인 없는 본문");
        assertThat(count("SELECT COUNT(*) FROM post WHERE id = ?", postId)).isZero();
    }

    @Test
    @DisplayName("한 신고에 판단은 한 번 — 다시 처리하면 409, 같은 글의 다른 신고는 '이미 없음' 이고 기록이 안 는다")
    void oneDecisionPerReport() throws Exception {
        User author = user("두 번 신고된 사람");
        User first = user("먼저 신고한 사람");
        User second = user("나중에 신고한 사람");
        long postId = newPost(author, "두 번 신고된 글", "본문");
        long firstReport = reportPost(first, postId);
        long secondReport = reportPost(second, postId);

        resolve(firstReport, "remove", "처음 처리").andExpect(status().isOk());
        resolve(firstReport, "remove", "다시 처리").andExpect(status().isConflict());
        resolve(firstReport, "dismiss", "마음을 바꿈").andExpect(status().isConflict());
        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE report_id = ?", firstReport))
                .as("409 는 아무것도 안 쓴다").isOne();

        JsonNode gone = body(resolve(secondReport, "remove", "같은 글").andExpect(status().isOk()));
        assertThat(targets(gone.path("removed"))).isEmpty();
        assertThat(targets(gone.path("alreadyGone"))).containsExactly("community_post:" + postId);
        assertThat(gone.path("actionIds")).isEmpty();
        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE report_id = ?", secondReport))
                .as("지운 것이 없으면 사본도 없다 — 빈 '지움' 줄을 쓰지 않는다").isZero();

        // 그 신고는 기각으로 닫는다(스크립트가 그렇게 안내한다).
        resolve(secondReport, "dismiss", "이미 지워진 글").andExpect(status().isOk());
        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE report_id = ? AND kind = 'dismiss'",
                secondReport)).isOne();
    }

    @Test
    @DisplayName("채팅 신고는 아직 지울 수 없다 — 409 이고 아무것도 안 쓴다. 기각은 된다")
    void chatReportsCannotBeRemovedYet() throws Exception {
        User reporter = user("채팅 신고한 사람");
        User sender = user("채팅 보낸 사람");
        long reportId = reports.file(reporter.getId(), sender.getId(), ReportReason.ABUSE, null,
                List.of(ReportSnapshotInput.target(ReportTarget.chatMessage(80_000 + nextSerial()), sender.getId(),
                        "채팅 보낸 사람", null, "채팅 본문", Instant.now()))).reportId();

        resolve(reportId, "remove", "채팅 욕설").andExpect(status().isConflict());
        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE report_id = ?", reportId)).isZero();

        resolve(reportId, "dismiss", "문제 없음").andExpect(status().isOk());
        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE report_id = ?", reportId)).isOne();
    }

    @Test
    @DisplayName("기각은 글을 그대로 두고 판단만 남긴다 — 사본도 대상도 없이")
    void dismissKeepsThePost() throws Exception {
        User author = user("억울한 사람");
        User reporter = user("오해한 사람");
        long postId = newPost(author, "문제없는 글", "문제없는 본문");
        long reportId = reportPost(reporter, postId);

        JsonNode result = body(resolve(reportId, "dismiss", "규정 위반 아님").andExpect(status().isOk()));

        assertThat(result.path("decision").asText()).isEqualTo("dismiss");
        assertThat(result.path("actionIds")).hasSize(1);
        mockMvc.perform(get("/api/community/posts/{id}", postId).header("Authorization", bearer(reporter)))
                .andExpect(status().isOk());
        Map<String, Object> action = jdbc.queryForMap("SELECT * FROM moderation_action WHERE report_id = ?", reportId);
        assertThat(action.get("kind")).isEqualTo("dismiss");
        assertThat(action.get("target_type")).isNull();
        assertThat(action.get("body")).isNull();
        assertThat(action.get("subject_user_id")).isNull();
        assertThat(action.get("reason")).isEqualTo("규정 위반 아님");
    }

    @Test
    @DisplayName("처리는 remove·dismiss 뿐이고 사유·이름이 있어야 한다(400), 없는 신고는 404 — 어느 쪽도 아무것도 안 쓴다")
    void badRequestsWriteNothing() throws Exception {
        User author = user("그대로인 사람");
        User reporter = user("잘못 부른 사람");
        long postId = newPost(author, "그대로인 글", "그대로인 본문");
        long reportId = reportPost(reporter, postId);

        resolve(reportId, "delete", "사유").andExpect(status().isBadRequest());
        resolve(reportId, "remove", "   ").andExpect(status().isBadRequest());
        resolve(reportId, "remove", "가".repeat(OperatorModeration.MAX_REASON + 1)).andExpect(status().isBadRequest());
        mockMvc.perform(onOperatorConnector(post("/internal/moderation/reports/{id}/resolve", reportId)
                        .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                        .param("decision", "remove")
                        .param("reason", "이름 없음")
                        .param("actor", " ")))
                .andExpect(status().isBadRequest());
        resolve(987_654_321L, "dismiss", "없는 신고").andExpect(status().isNotFound());

        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE report_id = ?", reportId)).isZero();
        assertThat(count("SELECT COUNT(*) FROM post WHERE id = ?", postId)).isOne();
    }

    @Test
    @DisplayName("본 입구로는 사용자 토큰도, role 을 ROLE_ADMIN 으로 위조한 토큰도 403 이고 글이 그대로다")
    void thePublicConnectorCannotRemove() throws Exception {
        User author = user("지켜질 사람");
        User attacker = user("남의 글을 지우려는 사람");
        long postId = newPost(author, "남의 글", "남의 본문");
        long reportId = reportPost(attacker, postId);
        String forgedAdmin = "Bearer " + jwtProvider.createAccessToken(attacker.getId(), "ROLE_ADMIN");

        for (String token : List.of(bearer(attacker), forgedAdmin)) {
            mockMvc.perform(post("/internal/moderation/reports/{id}/resolve", reportId)
                            .header("Authorization", token)
                            .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                            .param("decision", "remove")
                            .param("reason", "내 마음")
                            .param("actor", "attacker"))
                    .andExpect(status().isForbidden());
        }

        assertThat(count("SELECT COUNT(*) FROM post WHERE id = ?", postId)).isOne();
        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE report_id = ?", reportId)).isZero();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ResultActions resolve(long reportId, String decision, String reason) throws Exception {
        return mockMvc.perform(onOperatorConnector(post("/internal/moderation/reports/{id}/resolve", reportId)
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .param("decision", decision)
                .param("reason", reason)
                .param("actor", ACTOR)));
    }

    private long newPost(User author, String title, String text) throws Exception {
        return body(mockMvc.perform(post("/api/community/posts")
                        .header("Authorization", bearer(author))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(MAPPER.writeValueAsString(Map.of("board", "free", "title", title, "body", text))))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private long comment(User user, long postId, String text) throws Exception {
        return body(mockMvc.perform(post("/api/community/posts/{id}/comments", postId)
                        .header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(MAPPER.writeValueAsString(Map.of("body", text))))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private long reportPost(User reporter, long postId) throws Exception {
        return body(mockMvc.perform(post("/api/community/posts/{id}/reports", postId)
                        .header("Authorization", bearer(reporter))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"reason\":\"abuse\",\"memo\":\"운영자가 봐 주세요\"}"))
                .andExpect(status().isCreated())).path("reportId").asLong();
    }

    /**
     * 글에 붙은 사진 한 장 — 업로드 경로(S3 presign·확정)를 건너뛰고 붙은 상태의 행을 바로 쓴다.
     * 여기서 재는 것은 "지울 때 거두는가" 이고 올리는 길은 {@code MediaAttachmentIntegrationTest} 가 잰다.
     */
    private String attachPhoto(User owner, long postId) {
        String key = "posts/takedown-%d.jpg".formatted(postId);
        jdbc.update("INSERT INTO media_objects (created_at, size, media_key, owner_id, category, status, ref_type, ref_id) "
                        + "VALUES (NOW(6), 1, ?, ?, 'POST_IMAGE', 'ready', 'POST', ?)",
                key, String.valueOf(owner.getId()), String.valueOf(postId));
        return key;
    }

    private int count(String sql, Object... args) {
        Integer n = jdbc.queryForObject(sql, Integer.class, args);
        return n == null ? 0 : n;
    }

    private static List<String> targets(JsonNode list) {
        List<String> out = new ArrayList<>();
        list.forEach(t -> out.add(t.path("targetType").asText() + ":" + t.path("targetId").asLong()));
        return out;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }
}
