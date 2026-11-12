package com.heattrip.heat_trip_backend.moderationweb;

import com.heattrip.heat_trip_backend.moderation.ReportReason;
import com.heattrip.heat_trip_backend.moderation.ReportSnapshotInput;
import com.heattrip.heat_trip_backend.moderation.ReportTarget;
import com.heattrip.heat_trip_backend.moderation.Reports;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.servlet.mvc.method.annotation.RequestMappingHandlerMapping;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.request;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 운영자 경로는 <b>운영자 커넥터로 들어온 요청만</b> 통과한다 — 이슈 #718.
 *
 * <p>가짜 요청의 로컬 포트로 "어느 커넥터로 들어왔나" 를 흉내 낸다 — 설정은
 * {@link AbstractOperatorIntegrationTest} 에 있다. 실제 커넥터가 루프백에만 묶이는지는
 * {@code OperatorConnectorBindingTest} 가 따로 잰다. 지우기는 {@code OperatorTakedownIntegrationTest}.
 *
 * <h2>가장 중요한 검사 — 본 입구로는 어떤 토큰으로도 안 열린다</h2>
 * <p>운영자 권한을 토큰에 싣지 않는 것이 이 설계의 요점이다. 그래서 서명이 맞는 토큰에 role 을
 * {@code ROLE_ADMIN} 으로 적어 넣어도 403 이어야 한다. {@code users.role} 을 바꾸는 버그 하나가 곧 남의 글을
 * 지우는 권한이 되는 길을 막는 것이다.
 */
class OperatorModerationIntegrationTest extends AbstractOperatorIntegrationTest {

    @Autowired private Reports reports;
    @Autowired @Qualifier("requestMappingHandlerMapping") private RequestMappingHandlerMapping mappings;

    @Test
    @DisplayName("운영자 커넥터로 오면 신고 한 건과 그 사본을 본다 — 신고 대상과 맥락이 나뉘어 온다")
    void operatorSeesTheCase() throws Exception {
        long reporter = user("신고한 사람").getId();
        long author = user("쓴 사람").getId();
        long reportId = reports.file(reporter, author, ReportReason.ABUSE, "욕설입니다",
                List.of(ReportSnapshotInput.target(ReportTarget.post(9_000 + nextSerial()), author,
                        "쓴 사람", "제목", "신고된 본문", Instant.now()))).reportId();

        mockMvc.perform(onOperatorConnector(get("/internal/moderation/reports/{id}", reportId)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.reportId").value(reportId))
                .andExpect(jsonPath("$.reason").value("abuse"))
                .andExpect(jsonPath("$.memo").value("욕설입니다"))
                .andExpect(jsonPath("$.reportedUserId").value(author))
                .andExpect(jsonPath("$.targets[0].body").value("신고된 본문"))
                .andExpect(jsonPath("$.targets[0].targetType").value("community_post"))
                .andExpect(jsonPath("$.context").isEmpty());
    }

    @Test
    @DisplayName("없는 신고 번호는 404")
    void unknownReportIs404() throws Exception {
        mockMvc.perform(onOperatorConnector(get("/internal/moderation/reports/{id}", 987_654_321L)))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("본 입구로는 토큰이 없으면 401, 사용자 토큰은 403, role 을 ROLE_ADMIN 으로 위조한 토큰도 403")
    void publicConnectorNeverOpensTheOperatorPath() throws Exception {
        User someone = user("평범한 사용자");
        String userToken = jwtProvider.createAccessToken(someone.getId(), someone.getRole());
        String forgedAdmin = jwtProvider.createAccessToken(someone.getId(), "ROLE_ADMIN");

        mockMvc.perform(get("/internal/moderation/reports/1"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/internal/moderation/reports/1").header("Authorization", "Bearer " + userToken))
                .andExpect(status().isForbidden());
        mockMvc.perform(get("/internal/moderation/reports/1").header("Authorization", "Bearer " + forgedAdmin))
                .andExpect(status().isForbidden());
    }

    /**
     * {@code /internal/**} 의 <b>모든</b> 핸들러를 훑는다 — 다음 조각이 삭제·정지 경로를 더해도, 언젠가 다른
     * 모듈이 운영자 경로를 더해도 이 검사가 그대로 덮는다. 하나도 못 찾으면 그것도 실패다(빈 목록을 돌며 초록이
     * 되는 것을 막는다).
     */
    @Test
    @DisplayName("/internal 아래 모든 경로가 본 입구에서는 닫혀 있다 — 사용자 토큰으로 403")
    void everyInternalMappingIsClosedOnThePublicConnector() throws Exception {
        User someone = user("훑는 사용자");
        String userToken = jwtProvider.createAccessToken(someone.getId(), someone.getRole());

        List<String> probed = new ArrayList<>();
        for (var entry : mappings.getHandlerMethods().entrySet()) {
            Set<String> patterns = entry.getKey().getPatternValues();
            Set<RequestMethod> methods = entry.getKey().getMethodsCondition().getMethods();
            for (String pattern : patterns) {
                if (!pattern.startsWith("/internal/")) {
                    continue;
                }
                String path = pattern.replaceAll("\\{[^}]+}", "1");
                for (RequestMethod method : methods.isEmpty() ? Set.of(RequestMethod.GET) : methods) {
                    mockMvc.perform(request(method.asHttpMethod(), path).header("Authorization", "Bearer " + userToken))
                            .andExpect(status().isForbidden());
                    probed.add(method + " " + path);
                }
            }
        }
        assertThat(probed).as("운영자 경로를 하나도 못 찾았다 — 훑기가 늙었다").isNotEmpty();
    }

}
