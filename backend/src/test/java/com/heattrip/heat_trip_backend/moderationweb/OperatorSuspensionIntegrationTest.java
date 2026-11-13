package com.heattrip.heat_trip_backend.moderationweb;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.moderation.ReportReason;
import com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;
import com.heattrip.heat_trip_backend.moderation.entity.ModerationAction;
import com.heattrip.heat_trip_backend.moderation.repository.ModerationActionRepository;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 운영자가 사람을 정지하고 푼다 — 이슈 #718 셋째 조각.
 *
 * <h2>무엇을 지키나</h2>
 * <ol>
 *   <li><b>정지된 사람은 계정 삭제와 로그아웃만 한다</b> — 컨트롤러의 매핑을 전부 훑어 나머지가 하나도 빠짐없이
 *       403 {@code ACCOUNT_SUSPENDED} 인지 본다. 동의 관문은 {@code /api/**} 만 봐서 {@code /media}·{@code /auth}
 *       에 틈이 있었다. 같은 틈을 정지에 남기지 않으려고 목록을 손으로 적지 않고 훑는다 — 새 경로가 생겨도 덮인다.</li>
 *   <li><b>정지는 바로 먹는다</b> — 이미 가진 액세스 토큰으로도 막히고, refresh 토큰은 폐기돼 연장이 안 된다.</li>
 *   <li>기한이 지나면 저절로 풀리고, 풀면 바로 돌아온다. 다른 사람은 아무 영향이 없다.</li>
 *   <li>엉뚱한 사람을 내보내지 않는다 — 신고 번호를 주면 그 신고의 대상인지 확인한다.</li>
 *   <li>정지가 동의보다 먼저다 — 정지된 사람에게 "약관에 동의하세요" 를 보여 주지 않는다.</li>
 * </ol>
 */
class OperatorSuspensionIntegrationTest extends AbstractOperatorIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String ACTOR = "ops-test";
    private static final String SUSPENDED = "ACCOUNT_SUSPENDED";

    @Autowired private Reports reports;
    @Autowired private ModerationActionRepository actions;
    @Autowired private RefreshTokenService refreshTokens;
    @Autowired private JdbcTemplate jdbc;
    @Autowired @Qualifier("requestMappingHandlerMapping") private RequestMappingHandlerMapping mappings;

    @Test
    @DisplayName("정지된 사람은 계정 삭제와 로그아웃만 한다 — 나머지 모든 경로가 403 ACCOUNT_SUSPENDED")
    void aSuspendedUserCanOnlyDeleteTheAccountOrLogOut() throws Exception {
        User bad = user("내보낼 사람");
        long reportId = reportAgainst(bad);
        suspend(bad.getId(), reportId, null, "욕설 반복").andExpect(status().isOk());

        List<String> leaks = new ArrayList<>();
        Set<String> probed = new TreeSet<>();
        for (var entry : mappings.getHandlerMethods().entrySet()) {
            Set<RequestMethod> methods = entry.getKey().getMethodsCondition().getMethods();
            for (String pattern : entry.getKey().getPatternValues()) {
                if (pattern.startsWith("/internal/")) {
                    continue; // 운영자 통로 — 사람이 아니라 들어온 문으로 판정한다
                }
                String path = pattern.replaceAll("\\{[^}]+}", "1");
                for (RequestMethod method : methods.isEmpty() ? Set.of(RequestMethod.GET) : methods) {
                    String operation = method + " " + pattern;
                    if (operation.equals("DELETE /auth/me") || operation.equals("POST /auth/logout")) {
                        continue; // 열려 있어야 하는 둘 — 아래에서 따로 잰다
                    }
                    MockHttpServletResponse response = mockMvc.perform(request(method.asHttpMethod(), path)
                            .header("Authorization", bearer(bad))).andReturn().getResponse();
                    probed.add(operation);
                    if (response.getStatus() != 403 || !SUSPENDED.equals(code(response))) {
                        leaks.add(operation + " → " + response.getStatus() + " " + code(response));
                    }
                }
            }
        }

        assertThat(probed)
                .as("훑기가 경로를 거의 못 찾았다 — 매핑을 읽는 방법이 늙었다")
                .hasSizeGreaterThan(80)
                .contains("GET /auth/me", "PUT /auth/me", "POST /api/community/posts");
        assertThat(probed).as("사진 올리기도 훑었다 — 동의 관문의 틈이 여기 있었다").anyMatch(o -> o.contains("/media"));
        assertThat(leaks)
                .as("정지된 사람이 통과한 경로 — AccountSuspensionFilter 가 막아야 한다. 열어야 하는 것이라면 "
                        + "그 필터의 isOpen 과 이 검사를 함께 고친다")
                .isEmpty();

        mockMvc.perform(post("/auth/logout").header("Authorization", bearer(bad)))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/auth/me").header("Authorization", bearer(bad)))
                .andExpect(status().isNoContent());
        assertThat(users.findById(bad.getId())).as("정지된 사람도 탈퇴할 수 있다 — 개인정보를 지우지 못하고 갇히면 안 된다")
                .isEmpty();
    }

    @Test
    @DisplayName("정지는 바로 먹는다 — 가진 액세스 토큰으로도 막히고, refresh 토큰은 폐기돼 연장이 안 된다")
    void suspensionTakesEffectAtOnce() throws Exception {
        User bad = user("토큰 가진 사람");
        String refreshToken = refreshTokens.issueFor(bad.getId());
        mockMvc.perform(get("/auth/me").header("Authorization", bearer(bad))).andExpect(status().isOk());

        suspend(bad.getId(), null, null, "광고 도배").andExpect(status().isOk());

        MockHttpServletResponse blocked = mockMvc.perform(get("/auth/me").header("Authorization", bearer(bad)))
                .andReturn().getResponse();
        assertThat(blocked.getStatus()).isEqualTo(403);
        assertThat(code(blocked)).isEqualTo(SUSPENDED);
        assertThat(message(blocked))
                .as("무기한 정지에는 풀리는 시각이 없다")
                .contains("계정 삭제와 로그아웃만")
                .doesNotContain("풀립니다");
        mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(MAPPER.writeValueAsString(java.util.Map.of("refreshToken", refreshToken))))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("기간 정지는 풀리는 시각을 말하고, 기한이 지난 정지는 저절로 풀린다")
    void timedSuspensionsTellTheEndAndExpire() throws Exception {
        User timed = user("일주일 정지");
        JsonNode standing = body(suspend(timed.getId(), null, 7, "첫 위반").andExpect(status().isOk()));
        assertThat(standing.path("suspended").asBoolean()).isTrue();
        Instant endsAt = Instant.parse(standing.path("endsAt").asText());
        assertThat(endsAt).isBetween(Instant.now().plusSeconds(7 * 86_400 - 120), Instant.now().plusSeconds(7 * 86_400 + 120));
        MockHttpServletResponse blocked = mockMvc.perform(get("/auth/me").header("Authorization", bearer(timed)))
                .andReturn().getResponse();
        assertThat(message(blocked)).contains("풀립니다", "한국 시각");

        User expired = user("기한 지난 사람");
        LocalDateTime now = LocalDateTime.now(ZoneOffset.UTC);
        actions.save(ModerationAction.builder()
                .kind(ModerationAction.SUSPEND)
                .subjectUserId(expired.getId())
                .endsAt(now.minusMinutes(1))
                .reason("지난 정지")
                .actor(ACTOR)
                .createdAt(now.minusDays(3))
                .build());
        mockMvc.perform(get("/auth/me").header("Authorization", bearer(expired)))
                .andExpect(status().isOk());
        assertThat(body(mockMvc.perform(onOperatorConnector(get("/internal/moderation/users/{id}", expired.getId())))
                .andExpect(status().isOk())).path("suspended").asBoolean())
                .as("해제 줄 없이도 기한이 지나면 정지 중이 아니다").isFalse();
    }

    @Test
    @DisplayName("풀면 바로 돌아오고, 기록에는 정지와 해제가 최근 것부터 남는다 — 다른 사람은 내내 그대로다")
    void liftingRestoresAccessAndKeepsTheHistory() throws Exception {
        User bad = user("풀려날 사람");
        User bystander = user("옆 사람");
        long reportId = reportAgainst(bad);

        suspend(bad.getId(), reportId, 30, "반복 위반").andExpect(status().isOk());
        mockMvc.perform(get("/auth/me").header("Authorization", bearer(bystander))).andExpect(status().isOk());

        JsonNode lifted = body(lift(bad.getId(), "소명 확인").andExpect(status().isOk()));
        assertThat(lifted.path("suspended").asBoolean()).isFalse();
        mockMvc.perform(get("/auth/me").header("Authorization", bearer(bad))).andExpect(status().isOk());

        List<String> kinds = new ArrayList<>();
        lifted.path("history").forEach(line -> kinds.add(line.path("kind").asText()));
        assertThat(kinds).containsExactly("lift", "suspend");
        JsonNode suspension = lifted.path("history").get(1);
        assertThat(suspension.path("reportId").asLong()).isEqualTo(reportId);
        assertThat(suspension.path("reason").asText()).isEqualTo("반복 위반");
        assertThat(suspension.path("actor").asText()).isEqualTo(ACTOR);
        assertThat(suspension.path("endsAt").isNull()).as("30일 정지라 풀리는 시각이 있다").isFalse();
    }

    @Test
    @DisplayName("엉뚱한 사람을 내보내지 않는다 — 신고의 대상이 아니면 400, 없는 신고·사람은 404. 아무것도 안 쓴다")
    void theWrongPersonIsNeverSuspended() throws Exception {
        User reported = user("신고된 사람");
        User innocent = user("엉뚱한 사람");
        long reportId = reportAgainst(reported);

        suspend(innocent.getId(), reportId, null, "번호를 잘못 옮김").andExpect(status().isBadRequest());
        suspend(innocent.getId(), 987_654_321L, null, "없는 신고").andExpect(status().isNotFound());
        suspend(987_654_321L, null, null, "없는 사람").andExpect(status().isNotFound());
        suspend(innocent.getId(), null, 0, "0일").andExpect(status().isBadRequest());
        suspend(innocent.getId(), null, OperatorModeration.MAX_DAYS + 1, "너무 김").andExpect(status().isBadRequest());
        suspend(innocent.getId(), null, null, "  ").andExpect(status().isBadRequest());

        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE subject_user_id = ?", innocent.getId())).isZero();
        mockMvc.perform(get("/auth/me").header("Authorization", bearer(innocent))).andExpect(status().isOk());
    }

    @Test
    @DisplayName("정지 중에 다시 정지하거나 정지 아닌 사람을 풀면 409 — 기간을 바꾸려면 풀고 다시 건다")
    void doubleSuspensionAndNeedlessLiftConflict() throws Exception {
        User bad = user("두 번 정지될 뻔한 사람");

        lift(bad.getId(), "정지된 적 없음").andExpect(status().isConflict());
        suspend(bad.getId(), null, 7, "처음").andExpect(status().isOk());
        suspend(bad.getId(), null, null, "다시").andExpect(status().isConflict());

        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE subject_user_id = ?", bad.getId()))
                .as("409 는 아무것도 안 쓴다").isOne();
    }

    @Test
    @DisplayName("정지가 동의보다 먼저다 — 동의 안 한 채 정지된 사람에게는 정지 안내가 간다")
    void suspensionComesBeforeConsent() throws Exception {
        User unconsented = users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("operator-unconsented-%d@example.com".formatted(nextSerial()))
                .name("동의 안 한 사람")
                .nickname("동의 안 한 사람")
                .ageGroup(User.AgeGroup.OVER14)
                .build());
        MockHttpServletResponse before = mockMvc.perform(get("/api/community/bookmarks")
                .header("Authorization", bearer(unconsented))).andReturn().getResponse();
        assertThat(code(before)).as("전제: 이 경로는 동의 관문이 막는다").isEqualTo("CONSENT_REQUIRED");

        suspend(unconsented.getId(), null, null, "가입하자마자 도배").andExpect(status().isOk());

        MockHttpServletResponse after = mockMvc.perform(get("/api/community/bookmarks")
                .header("Authorization", bearer(unconsented))).andReturn().getResponse();
        assertThat(after.getStatus()).isEqualTo(403);
        assertThat(code(after)).isEqualTo(SUSPENDED);
    }

    @Test
    @DisplayName("본 입구로는 role 을 ROLE_ADMIN 으로 위조한 토큰으로도 정지·해제를 못 한다 — 403 이고 아무것도 안 쓴다")
    void thePublicConnectorCannotSuspend() throws Exception {
        User target = user("지켜질 사람");
        User attacker = user("남을 내보내려는 사람");
        String forgedAdmin = "Bearer " + jwtProvider.createAccessToken(attacker.getId(), "ROLE_ADMIN");

        for (String path : List.of("/internal/moderation/users/{id}/suspend", "/internal/moderation/users/{id}/lift")) {
            mockMvc.perform(post(path, target.getId())
                            .header("Authorization", forgedAdmin)
                            .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                            .param("reason", "내 마음")
                            .param("actor", "attacker"))
                    .andExpect(status().isForbidden());
        }

        assertThat(count("SELECT COUNT(*) FROM moderation_action WHERE subject_user_id = ?", target.getId())).isZero();
        mockMvc.perform(get("/auth/me").header("Authorization", bearer(target))).andExpect(status().isOk());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ResultActions suspend(long userId, Long reportId, Integer days, String reason) throws Exception {
        MockHttpServletRequestBuilder request = post("/internal/moderation/users/{id}/suspend", userId)
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .param("reason", reason)
                .param("actor", ACTOR);
        if (reportId != null) {
            request.param("reportId", String.valueOf(reportId));
        }
        if (days != null) {
            request.param("days", String.valueOf(days));
        }
        return mockMvc.perform(onOperatorConnector(request));
    }

    private ResultActions lift(long userId, String reason) throws Exception {
        return mockMvc.perform(onOperatorConnector(post("/internal/moderation/users/{id}/lift", userId)
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .param("reason", reason)
                .param("actor", ACTOR)));
    }

    /** 이 사람을 대상으로 한 신고 한 건 — 사본은 값으로만 들어간다(글이 실재할 필요가 없다). */
    private long reportAgainst(User reported) {
        User reporter = user("신고한 사람");
        return reports.file(reporter.getId(), reported.getId(), ReportReason.ABUSE, null,
                List.of(ReportSnapshotInput.target(ReportTarget.post(60_000 + nextSerial()), reported.getId(),
                        reported.getNickname(), "제목", "신고된 본문", Instant.now()))).reportId();
    }

    private int count(String sql, Object... args) {
        Integer n = jdbc.queryForObject(sql, Integer.class, args);
        return n == null ? 0 : n;
    }

    private static String code(MockHttpServletResponse response) throws Exception {
        return errorField(response, "code");
    }

    private static String message(MockHttpServletResponse response) throws Exception {
        return errorField(response, "message");
    }

    private static String errorField(MockHttpServletResponse response, String field) throws Exception {
        String raw = response.getContentAsString(StandardCharsets.UTF_8);
        if (raw.isBlank()) {
            return "";
        }
        try {
            return MAPPER.readTree(raw).path("error").path(field).asText("");
        } catch (Exception notJson) {
            return "";
        }
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }
}
