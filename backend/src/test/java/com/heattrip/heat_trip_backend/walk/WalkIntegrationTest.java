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
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
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

        String monday = thisWeek.atZone(KST).toLocalDate().toString();
        assertThat(stats.path("weekStart").asText())
                .as("응답이 스스로 기간을 말한다 — 월요일(KST) 이다(#209 Walks-medium-2)")
                .isEqualTo(monday);
        assertThat(stats.path("weekEnd").asText())
                .as("일요일(포함) = weekStart + 6일")
                .isEqualTo(thisWeek.atZone(KST).toLocalDate().plusDays(6).toString());
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

    // ─────────────── 회고 글 (#187) ───────────────
    //
    // 산책이 끝난 직후에 쓰는 글과 나중에 돌아보며 쓰는 글은 다르다. 예전에는 저장
    // 시점의 한 번이 전부였고, 잘못 쓰면 지우고 다시 만드는 수밖에 없었다.

    @Test
    @DisplayName("회고 글을 나중에 고칠 수 있다")
    void rewritesMemo() throws Exception {
        Account me = account("회고쓰는이");
        long dogId = dog(me, "콩이");
        long walkId = savedWalk(me, dogId, "\"처음 쓴 글\"");

        JsonNode after = body(memo(me, walkId, "{\"memo\":\"다시 쓴 글\"}")
                .andExpect(status().isOk()));

        assertThat(after.path("memo").asText()).isEqualTo("다시 쓴 글");

        JsonNode reread = body(mockMvc.perform(get("/api/walks/" + walkId)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));
        assertThat(reread.path("memo").asText())
                .as("응답만 바뀌고 저장이 안 되면 다시 열었을 때 옛 글이 나온다")
                .isEqualTo("다시 쓴 글");
    }

    @Test
    @DisplayName("빈 글은 \"다 지웠다\" 는 정상 요청이다 — 400 이 아니고 null 로 눕는다")
    void blankMemoClearsIt() throws Exception {
        Account me = account("글지우는이");
        long dogId = dog(me, "보리");
        long walkId = savedWalk(me, dogId, "\"지울 글\"");

        JsonNode after = body(memo(me, walkId, "{\"memo\":\"\"}")
                .andExpect(status().isOk()));

        assertThat(after.path("memo").isNull())
                .as("빈 문자열로 두면 \"안 썼다\" 가 두 모양이 되어 화면이 한쪽을 빠뜨린다")
                .isTrue();
    }

    @Test
    @DisplayName("{} 도 지운다 — 서버가 {} 와 {\"memo\":null} 을 구분하지 않으므로 계약도 그렇게 말한다")
    void emptyObjectClearsIt() throws Exception {
        Account me = account("빈본문으로지우는이");
        long dogId = dog(me, "감자");
        long walkId = savedWalk(me, dogId, "\"지울 글\"");

        JsonNode after = body(memo(me, walkId, "{}")
                .andExpect(status().isOk()));

        assertThat(after.path("memo").isNull())
                .as("""
                        2026-09-05 까지 계약은 memo 를 필수라 했지만 레코드 바인딩은 {} 와 \
                        {"memo":null} 을 같은 null 로 받는다. 코드가 못 지키는 required 를 \
                        계약에서 뗐다(#209 Walks-medium-3) — 이 테스트가 그 행동을 잠근다.""")
                .isTrue();
    }

    @Test
    @DisplayName("null 도 같은 뜻이다")
    void nullMemoClearsIt() throws Exception {
        Account me = account("널로지우는이");
        long dogId = dog(me, "탄이");
        long walkId = savedWalk(me, dogId, "\"지울 글\"");

        JsonNode after = body(memo(me, walkId, "{\"memo\":null}")
                .andExpect(status().isOk()));

        assertThat(after.path("memo").isNull()).isTrue();
    }

    @Test
    @DisplayName("501자는 400 이다")
    void rejectsTooLongMemo() throws Exception {
        Account me = account("장문가");
        long dogId = dog(me, "구름");
        long walkId = savedWalk(me, dogId, "null");

        memo(me, walkId, "{\"memo\":\"" + "가".repeat(501) + "\"}")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("500자는 통과한다 — 경계에서 한 글자 차이로 막지 않는다")
    void acceptsExactlyFiveHundred() throws Exception {
        Account me = account("딱맞는이");
        long dogId = dog(me, "나무");
        long walkId = savedWalk(me, dogId, "null");

        memo(me, walkId, "{\"memo\":\"" + "가".repeat(500) + "\"}")
                .andExpect(status().isOk());
    }

    @Test
    @DisplayName("남의 산책 글은 404 다 — 403 을 주면 그 id 가 있다는 것을 알려 준다")
    void othersWalkIsNotFound() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");
        long dogId = dog(owner, "복이");
        long walkId = savedWalk(owner, dogId, "\"내 글\"");

        memo(stranger, walkId, "{\"memo\":\"내가 고친다\"}")
                .andExpect(status().isNotFound());

        JsonNode still = body(mockMvc.perform(get("/api/walks/" + walkId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isOk()));
        assertThat(still.path("memo").asText())
                .as("404 를 주고도 실제로 고쳐 놓으면 그게 더 나쁘다")
                .isEqualTo("내 글");
    }

    @Test
    @DisplayName("없는 산책도 404 다")
    void missingWalkIsNotFound() throws Exception {
        Account me = account("없는것");
        memo(me, 999_999_999L, "{\"memo\":\"글\"}")
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("거리·시간은 글을 고쳐도 그대로다 — 회고가 기록 수정으로 번지지 않는다")
    void doesNotTouchMeasurements() throws Exception {
        Account me = account("숫자지키는이");
        long dogId = dog(me, "달이");
        long walkId = savedWalk(me, dogId, "null");

        JsonNode after = body(memo(me, walkId, "{\"memo\":\"글만 바꾼다\"}")
                .andExpect(status().isOk()));

        assertThat(after.path("distanceM").asInt()).isEqualTo(1200);
        assertThat(after.path("durationS").asInt()).isEqualTo(900);
    }

    // ─────────────── 점별 시각 (#155) ───────────────
    //
    // LINESTRING 은 x, y 만 담아서 점마다 몇 초에 찍혔는지가 어디에도 없었다. 시각은 그
    // 순간에만 있는 정보라 나중에 만들 수 없다 — 안 받으면 쌓인 행 전체에 대해 구간
    // 페이스·일시정지 복원·거리 재계산이 영영 불가능해진다.
    //
    // DB 에 CHECK 를 안 걸었으므로 **아래 검사가 유일한 방어선이다.**

    @Test
    @DisplayName("점별 시각을 경로와 함께 저장한다")
    void savesPathTimes() throws Exception {
        Account me = account("시각기록");
        long dogId = dog(me, "콩이");

        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":100,"durationS":7,
                 "path":[[126.9780,37.5665],[126.9800,37.5670],[126.9820,37.5675]],
                 "pathT":[0,3,7]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("응답에는 안 실린다 — 그리는 화면이 없다")
    void doesNotExposePathTimes() throws Exception {
        Account me = account("응답확인");
        long dogId = dog(me, "보리");

        JsonNode saved = body(save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":100,"durationS":7,
                 "path":[[126.9780,37.5665],[126.9800,37.5670]],"pathT":[0,7]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isCreated()));

        assertThat(saved.has("pathT"))
                .as("목록에서 path 를 뺀 것과 같은 이유다 — 쓰지 않는 것을 실으면 응답이 커진다")
                .isFalse();
    }

    @Test
    @DisplayName("길이가 다르면 400 이다 — 짝이 안 맞으면 어느 점이 언제인지 모른다")
    void rejectsMismatchedLength() throws Exception {
        Account me = account("길이불일치");
        long dogId = dog(me, "탄이");

        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":100,"durationS":7,
                 "path":[[126.9780,37.5665],[126.9800,37.5670],[126.9820,37.5675]],
                 "pathT":[0,7]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("경로 없이 시각만 보내면 400 이다")
    void rejectsTimesWithoutPath() throws Exception {
        Account me = account("경로없음");
        long dogId = dog(me, "구름");

        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":100,"durationS":7,
                 "pathT":[0,3,7]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("점이 하나뿐이면 400 이다 — 선이 못 되므로 시각만 남는다")
    void rejectsASinglePointWithTimes() throws Exception {
        Account me = account("점하나");
        long dogId = dog(me, "보리");

        // 점 하나는 LINESTRING 이 못 된다. 그런데 pathT 는 길이 1 로 짝이 맞아 보인다 —
        // 그대로 통과시키면 path = null · pathT = "[0]" 인 행이 남는다. 그 행은 경로가
        // 없는데 시각만 있어서, 나중에 구간 페이스를 계산하려는 쪽이 무엇을 보고
        // 계산해야 할지 알 수 없다.
        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":0,"durationS":7,
                 "path":[[126.9780,37.5665]],
                 "pathT":[0]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("점이 하나뿐이어도 시각을 안 보내면 저장된다 — 경로만 버린다")
    void keepsTheWalkWhenASinglePointComesWithoutTimes() throws Exception {
        Account me = account("점하나무시각");
        long dogId = dog(me, "달이");

        // 계약이 그렇게 말한다 — "점이 하나뿐이면 선이 아니므로 경로 없이 저장합니다".
        // 위 테스트가 막는 것은 "경로가 못 되는데 시각만 남는 것" 이지 산책 자체가 아니다.
        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":0,"durationS":7,
                 "path":[[126.9780,37.5665]]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("뒤로 흐르면 400 이다 — 시계가 거꾸로 간 것이다")
    void rejectsGoingBackwards() throws Exception {
        Account me = account("거꾸로");
        long dogId = dog(me, "달이");

        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":100,"durationS":7,
                 "path":[[126.9780,37.5665],[126.9800,37.5670]],"pathT":[7,3]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("음수면 400 이다 — 시작 전이다")
    void rejectsNegative() throws Exception {
        Account me = account("음수");
        long dogId = dog(me, "나무");

        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":100,"durationS":7,
                 "path":[[126.9780,37.5665],[126.9800,37.5670]],"pathT":[-1,3]}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(7)))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("안 보내도 저장된다 — 손입력 기록에는 시각이 없다")
    void pathTimesAreOptional() throws Exception {
        Account me = account("손입력");
        long dogId = dog(me, "복이");

        save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":2000,"durationS":1800}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(1800)))
                .andExpect(status().isCreated());
    }

    /** 글을 고치는 요청 하나. */
    private ResultActions memo(Account account, long walkId, String json) throws Exception {
        return mockMvc.perform(put("/api/walks/" + walkId + "/memo")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    /** 글이 든 산책 하나를 저장하고 id 를 돌려준다. */
    private long savedWalk(Account account, long dogId, String memoJson) throws Exception {
        return body(save(account, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":1200,"durationS":900,"memo":%s}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(900), memoJson))
                .andExpect(status().isCreated()))
                .path("id").asLong();
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
