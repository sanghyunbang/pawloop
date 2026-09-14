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
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Optional;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 모델 호출 비동기화 — 통계 요청은 모델을 기다리지 않는다. 처음 부를 때는 {@code aiSummary: null} 에
 * {@code aiSummaryPending: true} 로 <b>바로</b> 돌아오고, 문장은 요청 밖(실행기)에서 만들어져 다음 요청부터 실린다.
 * 같은 사람의 같은 주를 여러 요청이 동시에 부르면 모델은 <b>한 번</b>만 부른다.
 *
 * <p>모델은 목이고 래치로 붙들어 "만드는 중" 인 창을 실제로 연다. 이 클래스만 {@code async=true} 컨텍스트라
 * 따로 뜬다 — 다른 통합 테스트는 {@code application-test.properties} 의 {@code async=false} 로 예전처럼 동기다.
 */
@SpringBootTest(properties = "app.ai.weekly-insight.async=true")
@AutoConfigureMockMvc
class WeeklyInsightAsyncIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQ = new AtomicLong();
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");
    private static final String SENTENCE = "이번 주는 0회 걸었어요.\n쉬어 가는 주였네요.\n내일 한 번 어떠세요?";

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private WeeklyInsightRepository insights;

    @MockitoBean
    private WeeklyInsightModel model;

    @Test
    @DisplayName("처음 부르면 기다리지 않고 pending 으로 바로 돌아오고, 문장이 만들어지면 다음 요청에 실린다")
    void firstCallReturnsPendingAndTheNextCarriesTheSentence() throws Exception {
        CountDownLatch release = new CountDownLatch(1);
        AtomicInteger calls = new AtomicInteger();
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenAnswer(invocation -> {
            calls.incrementAndGet();
            release.await(10, TimeUnit.SECONDS);
            return Optional.of(SENTENCE);
        });
        Account me = account("비동기");

        long startedAt = System.nanoTime();
        JsonNode first = stats(me);
        long elapsedMs = (System.nanoTime() - startedAt) / 1_000_000;

        assertThat(first.path("aiSummary").isNull()).as("아직 문장이 없다").isTrue();
        assertThat(first.path("aiSummaryPending").asBoolean()).as("만드는 중이라고 말한다").isTrue();
        assertThat(elapsedMs).as("요청이 모델을 기다리지 않았다").isLessThan(5_000);

        // 만드는 중에 한 번 더 — 모델을 또 부르지 않는다(같은 사람 · 같은 주).
        JsonNode again = stats(me);
        assertThat(again.path("aiSummaryPending").asBoolean()).isTrue();

        release.countDown();
        WeeklyInsight row = awaitRow(me);
        assertThat(row.getText()).isEqualTo(SENTENCE);
        assertThat(calls.get()).as("동시에 두 번 물었지만 모델은 한 번").isEqualTo(1);

        JsonNode done = stats(me);
        assertThat(done.path("aiSummary").path("text").asText()).isEqualTo(SENTENCE);
        assertThat(done.path("aiSummaryPending").asBoolean()).isFalse();
        assertThat(calls.get()).as("캐시가 있으니 또 부르지 않는다").isEqualTo(1);
    }

    @Test
    @DisplayName("모델이 답을 못 주면 행이 없고, 다음 요청이 다시 만든다(그때도 pending)")
    void aFailedGenerationLeavesNoRowAndTheNextCallRetries() throws Exception {
        AtomicInteger calls = new AtomicInteger();
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenAnswer(invocation -> {
            calls.incrementAndGet();
            return Optional.empty();
        });
        Account me = account("실패");

        assertThat(stats(me).path("aiSummaryPending").asBoolean()).isTrue();
        awaitCalls(calls, 1);
        awaitIdle();
        assertThat(insights.findAll().stream().anyMatch(r -> r.getUser().getId().equals(me.id())))
                .as("실패한 시도는 행을 남기지 않는다").isFalse();

        assertThat(stats(me).path("aiSummaryPending").asBoolean()).as("다시 시도한다").isTrue();
        awaitCalls(calls, 2);
    }

    // ── 도우미 ─────────────────────────────────────────────

    private WeeklyInsight awaitRow(Account me) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (System.nanoTime() < deadline) {
            Optional<WeeklyInsight> row = insights.findByUser_IdAndDogKeyAndWeekStart(
                    me.id(), WeeklyInsight.ALL_DOGS, weekStart());
            if (row.isPresent() && row.get().getText() != null) {
                return row.get();
            }
            Thread.sleep(50);
        }
        throw new AssertionError("10초 안에 문장이 저장되지 않았다");
    }

    private static void awaitCalls(AtomicInteger calls, int expected) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (calls.get() < expected && System.nanoTime() < deadline) {
            Thread.sleep(50);
        }
        assertThat(calls.get()).isEqualTo(expected);
    }

    /** 실행기가 결과를 적을 시간 — 실패 경로는 적을 것이 없어 잠깐이면 된다. */
    private static void awaitIdle() throws Exception {
        Thread.sleep(300);
    }

    private static LocalDate weekStart() {
        LocalDate today = LocalDate.now(KST);
        return today.minusDays(today.getDayOfWeek().getValue() - 1L);
    }

    private JsonNode stats(Account me) throws Exception {
        return body(mockMvc.perform(get("/api/walks/stats/weekly")
                .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
    }

    private JsonNode body(ResultActions actions) throws Exception {
        return objectMapper.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    private Account account(String nickname) {
        long serial = SEQ.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("insight-async-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
