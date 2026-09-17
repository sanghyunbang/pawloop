package com.heattrip.heat_trip_backend.walk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.walk.ai.WeeklyInsightModel;
import com.heattrip.heat_trip_backend.walk.entity.WeeklyInsight;
import com.heattrip.heat_trip_backend.walk.repository.WeeklyInsightRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * AI 요약 👍/👎 — #486 후속. 요약 행에 평가 하나를 남기고, 통계 응답의 {@code aiSummary} 가 그것을 실어 준다.
 * 내 요약이 아니면 404, {@code up}·{@code down} 밖의 값은 400, {@code null} 은 지우기.
 *
 * <p>스프링 컨텍스트 설정은 {@code WeeklyInsightIntegrationTest} 와 같다(모델 목) — 캐시된 것을 다시 쓴다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
class WeeklyInsightFeedbackIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQ = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private WeeklyInsightRepository insights;

    @MockitoBean
    private WeeklyInsightModel model;

    @Test
    @DisplayName("👍 를 누르면 행에 up 과 시각이 남고 응답의 feedback 이 up 이다 · null 을 보내면 지워진다")
    void ratesAndClears() throws Exception {
        Account me = account("평가");
        long id = insight(me, "이번 주는 3회 걸었어요.\n좋아요.\n한 번 더 어떠세요?");

        JsonNode rated = body(rate(me, id, "{\"value\":\"up\"}").andExpect(status().isOk()));

        assertThat(rated.path("id").asLong()).isEqualTo(id);
        assertThat(rated.path("feedback").asText()).isEqualTo("up");
        WeeklyInsight row = insights.findById(id).orElseThrow();
        assertThat(row.getFeedback()).isEqualTo("up");
        assertThat(row.getFeedbackAt()).isNotNull();

        JsonNode cleared = body(rate(me, id, "{\"value\":null}").andExpect(status().isOk()));

        assertThat(cleared.path("feedback").isNull()).isTrue();
        row = insights.findById(id).orElseThrow();
        assertThat(row.getFeedback()).isNull();
        assertThat(row.getFeedbackAt()).as("지우면 시각도 함께").isNull();
    }

    @Test
    @DisplayName("통계 응답의 aiSummary 가 id 와 feedback 을 싣는다 — 앱은 그 id 로 누른다")
    void statsCarryTheIdAndFeedback() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenReturn(Optional.of(
                "이번 주는 0회 걸었어요.\n쉬어 가는 주였네요.\n내일 한 번 어떠세요?"));
        Account me = account("통계");

        JsonNode first = stats(me).path("aiSummary");
        assertThat(first.path("id").asLong()).isPositive();
        assertThat(first.path("feedback").isNull()).as("아직 안 눌렀다").isTrue();

        rate(me, first.path("id").asLong(), "{\"value\":\"down\"}").andExpect(status().isOk());

        assertThat(stats(me).path("aiSummary").path("feedback").asText()).isEqualTo("down");
    }

    @Test
    @DisplayName("남의 요약과 없는 요약은 404 — 둘을 구별해 주지 않는다")
    void rejectsSomeoneElsesInsight() throws Exception {
        Account me = account("나");
        Account other = account("남");
        long theirs = insight(other, "남의 문장");

        rate(me, theirs, "{\"value\":\"up\"}").andExpect(status().isNotFound());
        rate(me, 999_999L, "{\"value\":\"up\"}").andExpect(status().isNotFound());

        assertThat(insights.findById(theirs).orElseThrow().getFeedback()).isNull();
    }

    @Test
    @DisplayName("up · down 밖의 값은 400")
    void rejectsAnUnknownValue() throws Exception {
        Account me = account("이상한값");
        long id = insight(me, "문장");

        rate(me, id, "{\"value\":\"meh\"}").andExpect(status().isBadRequest());
        rate(me, id, "{\"value\":\"UP \"}").andExpect(status().isBadRequest());

        assertThat(insights.findById(id).orElseThrow().getFeedback()).isNull();
    }

    // ── 도우미 ─────────────────────────────────────────────

    private ResultActions rate(Account me, long insightId, String json) throws Exception {
        return mockMvc.perform(put("/api/walks/insights/{id}/feedback", insightId)
                .header("Authorization", "Bearer " + me.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private JsonNode stats(Account me) throws Exception {
        return body(mockMvc.perform(get("/api/walks/stats/weekly")
                .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
    }

    /** 요약 행 하나를 바로 심는다 — 모델을 안 부르고 평가만 잰다. */
    private long insight(Account me, String text) {
        User user = userRepository.findById(me.id()).orElseThrow();
        return insights.save(WeeklyInsight.first(user, WeeklyInsight.ALL_DOGS, LocalDate.of(2026, 9, 14),
                "hash-" + me.id(), "fake-model", text, LocalDateTime.of(2026, 9, 14, 0, 0))).getId();
    }

    private JsonNode body(ResultActions actions) throws Exception {
        return objectMapper.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    private Account account(String nickname) {
        long serial = SEQ.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("insight-fb-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
