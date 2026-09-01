package com.heattrip.heat_trip_backend.walk;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

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
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZonedDateTime;
import java.time.temporal.TemporalAdjusters;
import java.time.DayOfWeek;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 산책이 <b>실제로 남는지</b>를 HTTP 로 확인한다 — 이슈 #145 완료 조건 1·3·5·6.
 *
 * <p>애너테이션이 두 줄뿐인 것은 의도다 — {@code DogIntegrationTest} ·
 * {@code CareSharingIntegrationTest} 와 글자 그대로 같아야 스프링 컨텍스트 캐시를
 * 공유한다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
class WalkIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();
    private static final ZoneId KST = ZoneId.of("Asia/Seoul");

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    // ─────────────── 완료 조건 1 — 끝낸 산책이 서버에 남는다 ───────────────

    @Test
    @DisplayName("경로·거리·시간이 저장되고, 상세로 다시 꺼내면 좌표가 그대로다")
    void aWalkSurvivesTheRoundTrip() throws Exception {
        Account me = account("보리아빠");
        long dogId = dog(me, "보리");
        Instant started = Instant.now().minus(Duration.ofMinutes(30));

        JsonNode saved = body(save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","endedAt":"%s",
                 "distanceM":2400,"durationS":1800,
                 "path":[[126.9780,37.5665],[126.9800,37.5670],[126.9820,37.5680]],
                 "memo":"한강 한 바퀴","weather":"맑음 24°C"}
                """.formatted(dogId, UUID.randomUUID(), started, started.plusSeconds(1800)))
                .andExpect(status().isCreated()));

        assertThat(saved.path("distanceM").asInt()).isEqualTo(2400);
        assertThat(saved.path("durationS").asInt()).isEqualTo(1800);

        JsonNode detail = body(mockMvc.perform(get("/api/walks/{id}", saved.path("id").asLong())
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        JsonNode path = detail.path("path");
        assertThat(path.size()).isEqualTo(3);
        assertThat(path.get(0).get(0).asDouble())
                .as("[경도, 위도] 순서가 왕복해도 그대로여야 한다 (#24)")
                .isEqualTo(126.9780);
        assertThat(path.get(0).get(1).asDouble()).isEqualTo(37.5665);
        assertThat(detail.path("memo").asText()).isEqualTo("한강 한 바퀴");
    }

    @Test
    @DisplayName("경로 없이도 저장된다 — 손입력 기록과 위치 권한 거부가 그 경우다")
    void savesWithoutAPath() throws Exception {
        Account me = account("실내산책");
        long dogId = dog(me, "콩이");

        JsonNode saved = body(save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":800,"durationS":600}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(600)))
                .andExpect(status().isCreated()));

        assertThat(saved.path("path").isNull())
                .as("없는 경로를 만들어 넣지 않는다 — 화면이 거짓말을 한다")
                .isTrue();
    }

    // ─────────────── 완료 조건 3 — 뒤집힌 좌표를 서버가 거절한다 ───────────────

    @Test
    @DisplayName("좌표를 뒤집어 보내면 400 이다")
    void rejectsFlippedCoordinates() throws Exception {
        Account me = account("좌표실수");
        long dogId = dog(me, "보리");

        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":100,"durationS":100,
                 "path":[[37.5665,126.9780],[37.5670,126.9800]]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(100)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("말이 안 되는 값은 거절한다 — 다만 범위 검사는 진위를 말하지 않는다")
    void rejectsValuesOutsideTheSaneRange() throws Exception {
        Account me = account("범위");
        long dogId = dog(me, "보리");
        Instant now = Instant.now();

        // 지구 다섯 바퀴
        save(me, walkJson(dogId, now.minusSeconds(60), 999_999_999, 60))
                .andExpect(status().isBadRequest());
        // 이틀짜리 산책
        save(me, walkJson(dogId, now.minusSeconds(60), 1000, 200_000))
                .andExpect(status().isBadRequest());
        // 내일 산책을 미리
        save(me, walkJson(dogId, now.plus(Duration.ofHours(3)), 1000, 600))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("기기 시계가 몇 초 빨라도 저장된다 — 5분까지 봐준다")
    void toleratesASlightlyFastClock() throws Exception {
        Account me = account("빠른시계");
        long dogId = dog(me, "보리");

        save(me, walkJson(dogId, Instant.now().plusSeconds(60), 1000, 600))
                .andExpect(status().isCreated());
    }

    // ─────────────── 완료 조건 5 — 남의 산책과 없는 산책이 같은 404 ───────────────

    @Test
    @DisplayName("남의 산책과 없는 산책이 구분되지 않는 404 다")
    void othersWalkAndMissingWalkAreIndistinguishable() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");
        long dogId = dog(owner, "보리");

        long walkId = body(save(owner, walkJson(dogId, Instant.now().minusSeconds(600), 1000, 600))
                .andExpect(status().isCreated())).path("id").asLong();

        String othersWalk = mockMvc.perform(get("/api/walks/{id}", walkId)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();

        String missingWalk = mockMvc.perform(get("/api/walks/{id}", 999_999_999L)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();

        assertThat(withoutTraceId(othersWalk))
                .as("403 을 주면 id 를 훑어 남이 산책을 몇 번 했는지 셀 수 있다")
                .isEqualTo(withoutTraceId(missingWalk));
    }

    @Test
    @DisplayName("남의 반려동물 id 로는 저장할 수 없다")
    void cannotAttachAWalkToSomeoneElsesDog() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");
        long dogId = dog(owner, "보리");

        save(stranger, walkJson(dogId, Instant.now().minusSeconds(600), 1000, 600))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("삭제는 내 것만 된다. 지운 뒤에는 404 다")
    void deletesOnlyMine() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");
        long dogId = dog(owner, "보리");
        long walkId = body(save(owner, walkJson(dogId, Instant.now().minusSeconds(600), 1000, 600))
                .andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(delete("/api/walks/{id}", walkId)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/walks/{id}", walkId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNoContent());

        mockMvc.perform(get("/api/walks/{id}", walkId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNotFound());
    }

    // ─────────────── 완료 조건 6 — 두 번 보내도 두 줄이 되지 않는다 ───────────────

    @Test
    @DisplayName("같은 clientWalkId 를 다시 보내면 201 이 아니라 200 이고, 같은 행이 온다")
    void resendingDoesNotCreateASecondRow() throws Exception {
        Account me = account("재전송");
        long dogId = dog(me, "보리");
        String key = UUID.randomUUID().toString();
        String json = walkJson(dogId, Instant.now().minusSeconds(600), 1500, 900, key);

        JsonNode first = body(save(me, json).andExpect(status().isCreated()));
        JsonNode again = body(save(me, json).andExpect(status().isOk()));

        assertThat(again.path("id").asLong())
                .as("같은 산책이므로 같은 행이어야 한다")
                .isEqualTo(first.path("id").asLong());

        JsonNode page = body(mockMvc.perform(get("/api/walks")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(page.path("items").size())
                .as("두 줄이 되면 통계가 두 배가 되고, 사용자는 자기가 두 번 걸었다고 읽는다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("남이 같은 멱등키를 찍어도 내 산책이 새어 나가지 않는다")
    void anotherPersonsKeyDoesNotLeakMyWalk() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");
        long myDog = dog(owner, "보리");
        long theirDog = dog(stranger, "남의개");
        String key = UUID.randomUUID().toString();

        long mine = body(save(owner, walkJson(myDog, Instant.now().minusSeconds(600), 1500, 900, key))
                .andExpect(status().isCreated())).path("id").asLong();

        JsonNode theirs = body(save(stranger,
                walkJson(theirDog, Instant.now().minusSeconds(600), 2000, 1200, key))
                .andExpect(status().isCreated()));

        assertThat(theirs.path("id").asLong())
                .as("멱등키는 앱이 만드는 UUID 라 남의 키를 찍어 볼 수 있다. dog 별로 갈려야 한다")
                .isNotEqualTo(mine);
        assertThat(theirs.path("distanceM").asInt()).isEqualTo(2000);
    }

    // ─────────────── 목록과 통계 ───────────────

    @Test
    @DisplayName("목록에는 경로를 싣지 않는다 — 수천 점이면 응답이 메가바이트가 된다")
    void theListOmitsThePath() throws Exception {
        Account me = account("목록");
        long dogId = dog(me, "보리");
        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":1000,"durationS":600,
                 "path":[[126.9780,37.5665],[126.9800,37.5670]]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(600)))
                .andExpect(status().isCreated());

        JsonNode page = body(mockMvc.perform(get("/api/walks")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(page.path("items").get(0).path("path").isNull()).isTrue();
        assertThat(page.path("hasMore").asBoolean()).isFalse();
        assertThat(page.path("nextCursor").isNull())
                .as("마지막 장에서는 커서가 없다 — 계약이 그래서 required 에 안 넣었다")
                .isTrue();
    }

    @Test
    @DisplayName("커서로 다음 장을 받으면 겹치지도 건너뛰지도 않는다")
    void theCursorNeitherRepeatsNorSkips() throws Exception {
        Account me = account("커서");
        long dogId = dog(me, "보리");
        for (int i = 0; i < 5; i++) {
            save(me, walkJson(dogId, Instant.now().minusSeconds(600L + i), 1000 + i, 600))
                    .andExpect(status().isCreated());
        }

        JsonNode first = body(mockMvc.perform(get("/api/walks?limit=2")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
        assertThat(first.path("items").size()).isEqualTo(2);
        assertThat(first.path("hasMore").asBoolean()).isTrue();

        JsonNode second = body(mockMvc.perform(
                        get("/api/walks?limit=2&cursor=" + first.path("nextCursor").asText())
                                .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        var seen = new java.util.HashSet<Long>();
        first.path("items").forEach(w -> seen.add(w.path("id").asLong()));
        second.path("items").forEach(w -> assertThat(seen.add(w.path("id").asLong()))
                .as("장 경계에서 같은 행이 두 번 나오면 안 된다")
                .isTrue());
        assertThat(seen).hasSize(4);
    }

    @Test
    @DisplayName("깨진 커서는 400 이 아니라 첫 장이다 — 오래된 커서로 목록을 못 보면 안 된다")
    void anUnreadableCursorFallsBackToTheFirstPage() throws Exception {
        Account me = account("깨진커서");
        long dogId = dog(me, "보리");
        save(me, walkJson(dogId, Instant.now().minusSeconds(600), 1000, 600))
                .andExpect(status().isCreated());

        JsonNode page = body(mockMvc.perform(get("/api/walks?cursor=!!!not-base64!!!")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(page.path("items").size()).isEqualTo(1);
    }

    @Test
    @DisplayName("통계가 이번 주와 전체 기간을 한 번에 준다 — 화면 둘이 이 하나로 채워진다")
    void statsCarryBothPeriods() throws Exception {
        Account me = account("통계");
        long dogId = dog(me, "보리");

        // 이번 주 안에서 확실히 지난 시각. 주 시작 직후 + 1시간이면 KST 월요일 새벽이다.
        Instant thisWeek = thisWeekMondayOnePm();
        save(me, walkJson(dogId, thisWeek, 3000, 1800)).andExpect(status().isCreated());
        save(me, walkJson(dogId, thisWeek.plusSeconds(7200), 2000, 1200))
                .andExpect(status().isCreated());

        JsonNode stats = body(mockMvc.perform(get("/api/walks/stats/weekly")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(stats.path("weekKm").size())
                .as("계약이 '월~일 길이 7' 이라고 선언했다")
                .isEqualTo(7);
        assertThat(stats.path("weekKm").get(0).asDouble())
                .as("월요일이 0번이다. 두 산책이 같은 날이니 5.0km 다")
                .isEqualTo(5.0);
        assertThat(stats.path("walkCount").asInt())
                .as("산책한 '날 수' 가 아니라 '건수' 다 — 하루에 두 번이면 2 다")
                .isEqualTo(2);
        assertThat(stats.path("totalKm").asDouble()).isEqualTo(5.0);
        assertThat(stats.path("avgKm").asDouble()).isEqualTo(2.5);
        assertThat(stats.path("allTimeKm").asDouble()).isEqualTo(5.0);
        assertThat(stats.path("allTimeCount").asInt()).isEqualTo(2);
        assertThat(stats.path("allTimeMinutes").asInt())
                .as("1800 + 1200 초 = 50분")
                .isEqualTo(50);
        assertThat(stats.path("topPlaces").size())
                .as("walk 에 장소 축이 없다. 그럴듯한 값을 만들어 넣으면 화면이 거짓말을 한다")
                .isZero();
    }

    @Test
    @DisplayName("산책이 하나도 없어도 통계가 0 으로 온다 — 나눗셈을 하지 않는다")
    void statsWithoutAnyWalk() throws Exception {
        Account me = account("빈통계");

        JsonNode stats = body(mockMvc.perform(get("/api/walks/stats/weekly")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(stats.path("avgKm").asDouble()).isZero();
        assertThat(stats.path("allTimeCount").asInt()).isZero();
        assertThat(stats.path("weekKm").size()).isEqualTo(7);
    }

    @Test
    @DisplayName("토큰이 없으면 본문 없는 401 이다")
    void requiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/walks")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/walks/1")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/walks/stats/weekly")).andExpect(status().isUnauthorized());
        mockMvc.perform(delete("/api/walks/1")).andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/walks")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isUnauthorized());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** KST 기준 이번 주 월요일 13시. 지금보다 미래면 지난주 월요일로 내린다. */
    private static Instant thisWeekMondayOnePm() {
        ZonedDateTime monday = ZonedDateTime.now(KST)
                .with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
                .toLocalDate().atStartOfDay(KST).plusHours(13);
        return monday.toInstant().isAfter(Instant.now())
                ? monday.minusHours(13).toInstant()
                : monday.toInstant();
    }

    private static String walkJson(long dogId, Instant startedAt, int distanceM, int durationS) {
        return walkJson(dogId, startedAt, distanceM, durationS, UUID.randomUUID().toString());
    }

    private static String walkJson(long dogId, Instant startedAt, int distanceM, int durationS,
                                   String clientWalkId) {
        return """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":%d,"durationS":%d}
                """.formatted(dogId, clientWalkId, startedAt, distanceM, durationS);
    }

    private ResultActions save(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/walks")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private long dog(Account account, String name) throws Exception {
        return body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + account.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\",\"size\":\"small\"}".formatted(name)))
                .andExpect(status().isCreated()))
                .path("id").asLong();
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
    }

    private static String withoutTraceId(String body) {
        return body.replaceAll("\"traceId\":\"[^\"]*\"", "\"traceId\":\"·\"");
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("walk-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
