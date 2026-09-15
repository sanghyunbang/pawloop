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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
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

    @Test
    @DisplayName("숫자가 바뀌면 다시 만드는 동안 옛 문장을 안 싣는다 — pending 인데 문장이 옛것이면 카드가 거짓말을 한다 (#538)")
    void pendingDoesNotCarryTheOldSentence() throws Exception {
        CountDownLatch release = new CountDownLatch(1);
        AtomicInteger calls = new AtomicInteger();
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenAnswer(invocation -> {
            // 둘째 호출만 붙든다 — "다시 만드는 중" 인 창을 실제로 연다.
            if (calls.incrementAndGet() >= 2) {
                release.await(10, TimeUnit.SECONDS);
            }
            return Optional.of(SENTENCE);
        });
        Account me = account("낡음");

        stats(me);
        awaitRow(me);
        assertThat(stats(me).path("aiSummary").path("text").asText())
                .as("첫 문장은 그때의 숫자로 쓴 것이다").isEqualTo(SENTENCE);

        // 아이를 등록하면 모델에 주는 글이 바뀐다(크기 · 나이대 한 줄이 붙는다) — 산책이 하나 는 것과 같다.
        dog(me, "보리");
        JsonNode changed = stats(me);

        assertThat(changed.path("aiSummaryPending").asBoolean())
                .as("다시 만드는 중이라고 말한다").isTrue();
        assertThat(changed.path("aiSummary").isNull())
                .as("""
                        옛 문장은 다른 입력으로 쓴 것이다. 만드는 동안 그것을 함께 실으면 카드가 \
                        바로 위 "이번 주 요약" 과 다른 말을 한다 (#538).""")
                .isTrue();

        release.countDown();
        // **부른 횟수가 아니라 다 쓴 것을 기다린다.** complete() 가 돌아온 뒤에도 실행기 스레드는
        // 숫자 검사와 저장을 더 하고, 저장은 model.name() 을 부른다. 거기서 멈추면 그 스레드가
        // 다음 테스트의 when(model.name()) 과 같은 목을 동시에 건드려 스터빙이 깨진다
        // (ClassCastException: Boolean cannot be cast to String).
        awaitRegenerated(me);
    }

    // ── 도우미 ─────────────────────────────────────────────

    private void dog(Account me, String name) throws Exception {
        mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + me.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s","breed":"푸들","size":"small","birth":"2024-09-01","neutered":false}
                                """.formatted(name)))
                .andExpect(status().isCreated());
    }

    /** 다시 만들기가 **끝날** 때까지 — 행의 `calls` 가 둘이 되면 저장까지 끝난 것이다. */
    private void awaitRegenerated(Account me) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(10);
        while (System.nanoTime() < deadline) {
            Optional<WeeklyInsight> row = insights.findByUser_IdAndDogKeyAndWeekStart(
                    me.id(), WeeklyInsight.ALL_DOGS, weekStart());
            if (row.isPresent() && row.get().getCalls() >= 2) {
                return;
            }
            Thread.sleep(50);
        }
        throw new AssertionError("10초 안에 다시 만들어지지 않았다");
    }

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
