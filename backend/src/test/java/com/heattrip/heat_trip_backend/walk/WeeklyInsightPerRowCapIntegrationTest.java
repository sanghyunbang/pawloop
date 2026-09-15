package com.heattrip.heat_trip_backend.walk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.walk.ai.WeeklyInsightModel;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 요약 하나의 하루 상한 — 이슈 #538.
 *
 * <p>상한 자체는 {@code WeeklyInsightServiceTest} 가 값으로 잰다. 여기서 재는 것은 <b>그 상한이
 * 실제로 물려 있는가</b>다 — 상한에 닿았을 때 모델을 안 부르고, <b>옛 문장도 안 내보내는가</b>.
 * 예전 상한(주당 3회)의 버그가 정확히 여기였다: 안 부르는 것까지는 맞았는데 옛 문장을 그대로
 * 내보내 카드가 "이번 주 0km" 라고 말했다.
 *
 * <p>상한을 1 로 두면 첫 생성 뒤에는 한 번도 못 부른다. 그 자리를 본다.
 */
@SpringBootTest(properties = "app.ai.weekly-insight.per-row-daily-cap=1")
@AutoConfigureMockMvc
class WeeklyInsightPerRowCapIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQ = new AtomicLong();
    private static final String SENTENCE = "이번 주도 걸었어요.\n좋아요.\n계속해요.";

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;

    @MockitoBean
    private WeeklyInsightModel model;

    @Test
    @DisplayName("하루 상한에 닿으면 모델을 안 부르고, 옛 문장도 안 내보낸다 — 카드가 없다 (#538)")
    void whenTheDailyCapIsReachedThereIsNoCardAtAll() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenReturn(Optional.of(SENTENCE));
        Account me = account("상한");

        assertThat(stats(me).path("aiSummary").path("text").asText())
                .as("첫 번째는 만든다 — 상한 1 의 한 칸").isEqualTo(SENTENCE);

        // 아이를 등록하면 모델에 주는 글이 바뀐다 — 산책이 하나 는 것과 같다.
        dog(me, "보리");
        JsonNode capped = stats(me);

        verify(model, times(1)).complete(anyString(), anyString());
        assertThat(capped.path("aiSummary").isNull())
                .as("""
                        상한에 닿았다고 옛 문장을 내보내면, 그 문장은 바뀌기 전 숫자로 쓴 것이라 \
                        바로 위 "이번 주 요약" 카드와 다른 말을 한다 (#538).""")
                .isTrue();
        assertThat(capped.path("aiSummaryPending").asBoolean())
                .as("만드는 중이 아니다 — 앱이 헛되이 다시 읽지 않는다").isFalse();
    }

    // ── 도우미 ─────────────────────────────────────────────

    private JsonNode stats(Account me) throws Exception {
        return body(mockMvc.perform(get("/api/walks/stats/weekly")
                .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
    }

    private void dog(Account me, String name) throws Exception {
        mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + me.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s","breed":"푸들","size":"small","birth":"2024-09-01","neutered":false}
                                """.formatted(name)))
                .andExpect(status().isCreated());
    }

    private JsonNode body(ResultActions actions) throws Exception {
        return objectMapper.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    private Account account(String nickname) {
        long serial = SEQ.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("insight-cap-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
