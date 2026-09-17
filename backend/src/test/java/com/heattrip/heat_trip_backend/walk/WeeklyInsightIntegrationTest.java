package com.heattrip.heat_trip_backend.walk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.walk.ai.InsightNumberGuard;
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

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * AI 주간 요약 — 이슈 #486. 모델은 가짜({@link MockitoBean})다: 키 없이 "캐시 · 숫자 검사 · 재생성 · 상한"
 * 을 잰다. 진짜 모델의 문장은 통제할 수 없어 여기서 잴 것이 아니다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class WeeklyInsightIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQ = new AtomicLong();
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private WeeklyInsightRepository insights;

    @MockitoBean
    private WeeklyInsightModel model;

    @Test
    @DisplayName("모델이 없으면(키 없음) aiSummary 는 null 이고 부르지도 않는다")
    void nullWhenTheModelIsUnavailable() throws Exception {
        when(model.available()).thenReturn(false);
        Account me = account("키없음");

        JsonNode stats = stats(me);

        assertThat(stats.has("aiSummary")).as("필드는 계약에 늘 있다 — 값이 null").isTrue();
        assertThat(stats.path("aiSummary").isNull()).isTrue();
        verify(model, never()).complete(anyString(), anyString());
    }

    @Test
    @DisplayName("모델의 문장이 입력의 숫자만 쓰면 aiSummary 로 나가고, 같은 주에 두 번 부르면 한 번만 호출(캐시)")
    void attachesTheSentenceAndCachesItForTheWeek() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenReturn(Optional.of(
                "이번 주는 1회 걸어 1.5km 를 채웠어요.\n아침 산책이 잘 맞는 것 같아요.\n내일 한 번 더 어떠세요?"));
        Account me = account("캐시");
        walkWithDog(me, dog(me, "보리"), 1500, 1200);

        JsonNode first = stats(me);
        JsonNode second = stats(me);

        assertThat(first.path("aiSummary").path("text").asText()).contains("1.5km");
        assertThat(first.path("aiSummary").path("generatedAt").asText()).isNotBlank();
        assertThat(second.path("aiSummary").path("text").asText())
                .isEqualTo(first.path("aiSummary").path("text").asText());
        verify(model, times(1)).complete(anyString(), anyString());

        WeeklyInsight row = insights.findByUser_IdAndDogKeyAndWeekStart(
                me.id(), WeeklyInsight.ALL_DOGS, LocalDate.parse(first.path("weekStart").asText())).orElseThrow();
        assertThat(row.getModel()).isEqualTo("fake-model");
        assertThat(row.getCalls()).isEqualTo(1);
    }

    @Test
    @DisplayName("입력에 없는 숫자를 쓴 문장은 버린다 — aiSummary null, 같은 입력엔 다시 안 부른다")
    void discardsASentenceWithAnInventedNumber() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenReturn(Optional.of("이번 주 5km 를 걸었어요."));
        Account me = account("지어냄");
        walkWithDog(me, dog(me, "보리"), 1500, 1200);

        JsonNode first = stats(me);
        JsonNode second = stats(me);

        assertThat(first.path("aiSummary").isNull()).isTrue();
        assertThat(second.path("aiSummary").isNull()).isTrue();
        verify(model, times(1)).complete(anyString(), anyString());
        assertThat(insights.findByUser_IdAndDogKeyAndWeekStart(
                me.id(), WeeklyInsight.ALL_DOGS, LocalDate.parse(first.path("weekStart").asText()))
                .orElseThrow().getText()).as("버린 것도 행으로 남는다 — 같은 입력에 같은 실수를 반복하지 않게").isNull();
    }

    @Test
    @DisplayName("안 걸은 요일을 말한 문장은 버린다 — 숫자 검사는 요일 이름을 안 본다 (#543)")
    void discardsASentenceNamingADayWithNoWalk() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        // 요일 일곱을 한 줄로 늘어놓는다 — 어느 요일에 돌려도 0km 인 요일이 여섯 들어간다.
        // 숫자가 하나도 없어서 숫자 검사는 통과한다. 그게 #543 이 새 가드를 부른 이유다.
        when(model.complete(anyString(), anyString()))
                .thenReturn(Optional.of("이번 주는 월·화·수·목·금·토·일에 걸었어요."));
        Account me = account("요일");
        walkWithDog(me, dog(me, "보리"), 1500, 1200);

        JsonNode stats = stats(me);

        assertThat(InsightNumberGuard.allowed("이번 주는 월·화·수·목·금·토·일에 걸었어요.", ""))
                .as("숫자가 없으니 숫자 검사는 통과한다 — 이 문장을 막는 것은 요일 검사다")
                .isTrue();
        assertThat(stats.path("aiSummary").isNull()).isTrue();
    }

    @Test
    @DisplayName("걸은 요일을 말한 문장은 그대로 나간다 — 요일 검사가 전부를 버리는 것이 아니다 (#543)")
    void keepsASentenceNamingTheDayThatWasWalked() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        // `walkWithDog` 이 한 시간 전으로 적는다 — 그 시각의 요일이 유일하게 km 가 있는 요일이다.
        String day = "월화수목금토일".substring(walkedDayIndex(), walkedDayIndex() + 1);
        when(model.complete(anyString(), anyString()))
                .thenReturn(Optional.of(day + "요일에 걸었어요.\n좋아요.\n계속해요."));
        Account me = account("걸은요일");
        walkWithDog(me, dog(me, "보리"), 1500, 1200);

        JsonNode stats = stats(me);

        assertThat(stats.path("aiSummary").path("text").asText()).contains(day + "요일");
    }

    /** {@code walkWithDog} 이 적는 산책의 요일 — 월요일이 0. 자정 근처에서도 안 흔들리게 같은 식으로 잰다. */
    private static int walkedDayIndex() {
        return Instant.now().atZone(KST).minusHours(1).getDayOfWeek().getValue() - 1;
    }

    @Test
    @DisplayName("새 산책이 오면(입력이 바뀌면) 그때마다 다시 만든다 — 주당 상한으로 멈추지 않는다 (#538)")
    void regeneratesEveryTimeTheInputChanges() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenReturn(Optional.of("이번 주도 걸었어요.\n좋아요.\n계속해요."));
        Account me = account("재생성");
        long dog = dog(me, "보리");

        stats(me);                       // 1 — 산책 없음
        walkWithDog(me, dog, 1000, 600);
        stats(me);                       // 2 — 입력 바뀜
        walkWithDog(me, dog, 1000, 600);
        stats(me);                       // 3 — 입력 바뀜
        walkWithDog(me, dog, 1000, 600);
        JsonNode fourth = stats(me);     // 4 — 예전에는 여기서 멈추고 옛 문장을 내보냈다

        verify(model, times(4)).complete(anyString(), anyString());
        assertThat(fourth.path("aiSummary").path("text").asText()).contains("걸었어요");
    }

    @Test
    @DisplayName("숫자가 바뀌었는데 다시 못 만들면 옛 문장을 안 내보낸다 — 위 카드와 다른 말을 하느니 카드를 안 그린다 (#538)")
    void neverServesASentenceWrittenForOtherNumbers() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        // 처음엔 문장을 주고, 그다음부터는 못 준다(시간 초과 · 망). 그래서 새 문장이 안 쌓인다.
        when(model.complete(anyString(), anyString()))
                .thenReturn(Optional.of("이번 주 1km 걸었어요.\n좋아요.\n계속해요."))
                .thenReturn(Optional.empty());
        Account me = account("낡음");
        long dog = dog(me, "보리");
        walkWithDog(me, dog, 1000, 600);

        JsonNode first = stats(me);
        assertThat(first.path("aiSummary").path("text").asText())
                .as("처음엔 그 주의 숫자로 쓴 문장이다").contains("1km");

        walkWithDog(me, dog, 900, 540);   // 이번 주 숫자가 1km 에서 1.9km 로 바뀐다
        JsonNode second = stats(me);

        assertThat(second.path("aiSummary").isNull())
                .as("""
                        1km 이라고 쓴 문장을 1.9km 인 주에 그대로 내보내면, 바로 위 "이번 주 요약" \
                        카드가 1.9km 라고 말하는 옆에서 다른 숫자를 말한다 (#538).""")
                .isTrue();
        assertThat(insights.findByUser_IdAndDogKeyAndWeekStart(
                me.id(), WeeklyInsight.ALL_DOGS, LocalDate.parse(second.path("weekStart").asText())))
                .as("행은 그대로 있다 — 지우는 것이 아니라 안 내보내는 것이다")
                .isPresent();
    }

    @Test
    @DisplayName("모델이 답을 못 주면(시간 초과 · 망) 이번엔 null 이고 행을 남기지 않아 다음에 다시 시도한다")
    void retriesLaterWhenTheModelFails() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenReturn(Optional.empty());
        Account me = account("실패");

        JsonNode first = stats(me);
        stats(me);

        assertThat(first.path("aiSummary").isNull()).isTrue();
        verify(model, times(2)).complete(anyString(), anyString());
        assertThat(insights.findByUser_IdAndDogKeyAndWeekStart(
                me.id(), WeeklyInsight.ALL_DOGS, LocalDate.parse(first.path("weekStart").asText()))).isEmpty();
    }

    @Test
    @DisplayName("모델에 주는 글에는 아이 이름 · 장소 · 좌표가 없다 — 통계 숫자와 크기 · 나이대뿐")
    void sendsOnlyAggregatesToTheModel() throws Exception {
        when(model.available()).thenReturn(true);
        when(model.name()).thenReturn("fake-model");
        when(model.complete(anyString(), anyString())).thenReturn(Optional.of("이번 주도 걸었어요.\n좋아요.\n계속해요."));
        Account me = account("최소입력");
        long dog = dog(me, "보리");
        walkWithDog(me, dog, 1500, 1200);

        stats(me);

        org.mockito.ArgumentCaptor<String> sent = org.mockito.ArgumentCaptor.forClass(String.class);
        verify(model).complete(anyString(), sent.capture());
        assertThat(sent.getValue()).doesNotContain("보리").doesNotContain("127.").doesNotContain("서울숲")
                .contains("1.5km").contains("소형견");
    }

    // ── 도우미 ─────────────────────────────────────────────

    private JsonNode stats(Account me) throws Exception {
        return body(mockMvc.perform(get("/api/walks/stats/weekly")
                .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
    }


    private void walkWithDog(Account me, long dogId, int distanceM, int durationS) throws Exception {
        String startedAt = Instant.now().atZone(KST).minusHours(1).toInstant().toString();
        mockMvc.perform(post("/api/walks")
                        .header("Authorization", "Bearer " + me.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"clientWalkId":"%s","startedAt":"%s","distanceM":%d,"durationS":%d,"dogId":%d,
                                 "place":{"source":"kto","contentId":"2733847","title":"서울숲"}}
                                """.formatted(java.util.UUID.randomUUID(), startedAt, distanceM, durationS, dogId)))
                .andExpect(status().isCreated());
    }

    private long dog(Account me, String name) throws Exception {
        return body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + me.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"%s","breed":"푸들","size":"small","birth":"2024-09-01","neutered":false}
                                """.formatted(name)))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private JsonNode body(ResultActions actions) throws Exception {
        return objectMapper.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    private Account account(String nickname) {
        long serial = SEQ.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("insight-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
