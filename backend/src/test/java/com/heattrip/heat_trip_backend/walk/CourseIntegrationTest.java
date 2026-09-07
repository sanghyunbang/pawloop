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

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 내 경로를 코스로 — 이슈 #339.
 *
 * <p>여기서 재는 것은 셋이다. <b>집 앞이 남지 않는가</b>(양 끝 100m 가 잘렸는가),
 * <b>남의 비공개가 새지 않는가</b>(없는 것과 같은 404), <b>공개한 것만 이웃에게 보이는가</b>.
 *
 * <p>애너테이션이 두 줄뿐인 것은 의도다 — 다른 통합 테스트와 글자 그대로 같아야 스프링
 * 컨텍스트 캐시를 공유한다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
class CourseIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Test
    @DisplayName("산책을 코스로 남기면 양 끝 100m 가 잘린다 — 집 앞이 남지 않는다")
    void trimsTheEndsWhenSavingACourse() throws Exception {
        Account me = account("코스");
        long dogId = dog(me, "보리");
        long walkId = walk(me, dogId, 61, 10);

        JsonNode course = body(saveCourse(me, """
                {"walkId":%d,"name":"서울숲 한 바퀴","note":"그늘이 많아요","tags":["shade","poopbag"]}
                """.formatted(walkId)).andExpect(status().isCreated()));

        assertThat(course.path("name").asText()).isEqualTo("서울숲 한 바퀴");
        assertThat(course.path("visibility").asText())
                .as("공개는 사용자가 명시적으로 하는 일이다")
                .isEqualTo("private");
        assertThat(course.path("mine").asBoolean()).isTrue();
        assertThat(course.path("distanceM").asInt())
                .as("600m 에서 앞뒤 100m 씩을 버리면 400m 쯤이다")
                .isBetween(380, 420);

        JsonNode path = course.path("path");
        assertThat(path.size()).isGreaterThan(1);
        double firstLng = path.get(0).get(0).asDouble();
        assertThat(firstLng)
                .as("시작점이 원래 시작점(127.0400)이 아니다")
                .isGreaterThan(127.0400);
        assertThat(course.path("tags").toString()).contains("shade").contains("poopbag");
    }

    @Test
    @DisplayName("300m 가 안 되는 산책은 코스가 되지 않는다 — 이유를 말한다")
    void refusesAShortWalk() throws Exception {
        Account me = account("짧은");
        long dogId = dog(me, "보리");
        long walkId = walk(me, dogId, 21, 10);

        String error = saveCourse(me, """
                {"walkId":%d,"name":"너무 짧은 길"}
                """.formatted(walkId))
                .andExpect(status().isBadRequest())
                .andReturn().getResponse().getContentAsString(java.nio.charset.StandardCharsets.UTF_8);

        assertThat(error).contains("300m");
    }

    @Test
    @DisplayName("경로 없는 산책은 코스가 되지 않는다 — 손입력 기록이다")
    void refusesAWalkWithoutAPath() throws Exception {
        Account me = account("손입력");
        long dogId = dog(me, "보리");
        long walkId = body(save(me, """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":1200,"durationS":900}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(3600)))
                .andExpect(status().isCreated())).path("id").asLong();

        saveCourse(me, """
                {"walkId":%d,"name":"경로 없는 길"}
                """.formatted(walkId))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("남의 비공개 코스는 없는 코스와 같은 404 — 공개하면 보인다")
    void hidesAnotherPersonsPrivateCourse() throws Exception {
        Account owner = account("주인");
        Account neighbour = account("이웃");
        long dogId = dog(owner, "보리");
        long walkId = walk(owner, dogId, 61, 10);
        long courseId = body(saveCourse(owner, """
                {"walkId":%d,"name":"우리 동네 길"}
                """.formatted(walkId)).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(get("/api/courses/{id}", courseId)
                        .header("Authorization", "Bearer " + neighbour.token()))
                .andExpect(status().isNotFound());

        JsonNode publicBefore = body(mockMvc.perform(get("/api/courses/public")
                        .header("Authorization", "Bearer " + neighbour.token()))
                .andExpect(status().isOk()));
        assertThat(idsOf(publicBefore)).doesNotContain(courseId);

        mockMvc.perform(put("/api/courses/{id}/visibility", courseId)
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"visibility\":\"public\"}"))
                .andExpect(status().isOk());

        JsonNode seen = body(mockMvc.perform(get("/api/courses/{id}", courseId)
                        .header("Authorization", "Bearer " + neighbour.token()))
                .andExpect(status().isOk()));
        assertThat(seen.path("mine").asBoolean())
                .as("이웃에게는 내 것이 아니다")
                .isFalse();
        assertThat(seen.path("path").size()).isGreaterThan(1);

        JsonNode publicAfter = body(mockMvc.perform(get("/api/courses/public")
                        .header("Authorization", "Bearer " + neighbour.token()))
                .andExpect(status().isOk()));
        assertThat(idsOf(publicAfter)).contains(courseId);
    }

    @Test
    @DisplayName("공개 목록은 좌표를 받지 않는다 — 가까운 것 고르기는 기기가 한다")
    void publicListTakesNoCoordinates() throws Exception {
        Account me = account("좌표없음");

        JsonNode list = body(mockMvc.perform(get("/api/courses/public?lat=37.5&lng=127.0")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(list.isArray())
                .as("좌표를 붙여 불러도 그냥 목록이다 — 서버가 그것으로 거르지 않는다")
                .isTrue();
    }

    @Test
    @DisplayName("내 목록은 선을 빼고 시작점만 준다 — 목록에 선 수십 개를 실을 이유가 없다")
    void listsMyCoursesWithoutFullPaths() throws Exception {
        Account me = account("목록");
        long dogId = dog(me, "보리");
        long walkId = walk(me, dogId, 61, 10);
        saveCourse(me, """
                {"walkId":%d,"name":"첫 코스"}
                """.formatted(walkId)).andExpect(status().isCreated());

        JsonNode mine = body(mockMvc.perform(get("/api/courses/me")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(mine.size()).isEqualTo(1);
        assertThat(mine.get(0).path("path").size())
                .as("시작점 하나뿐이다")
                .isEqualTo(1);
        assertThat(mine.get(0).path("name").asText()).isEqualTo("첫 코스");
    }

    @Test
    @DisplayName("지우는 것은 내 코스만 — 남의 것은 404 이고 그대로 남는다")
    void deletesOnlyMyCourse() throws Exception {
        Account owner = account("삭제주인");
        Account other = account("남");
        long dogId = dog(owner, "보리");
        long walkId = walk(owner, dogId, 61, 10);
        long courseId = body(saveCourse(owner, """
                {"walkId":%d,"name":"지울 코스","visibility":"public"}
                """.formatted(walkId)).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(delete("/api/courses/{id}", courseId)
                        .header("Authorization", "Bearer " + other.token()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/api/courses/{id}", courseId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isOk());

        mockMvc.perform(delete("/api/courses/{id}", courseId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNoContent());
        mockMvc.perform(get("/api/courses/{id}", courseId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("남의 산책으로는 코스를 만들 수 없다 — 없는 산책과 같은 404")
    void refusesAnotherPersonsWalk() throws Exception {
        Account owner = account("산책주인");
        Account thief = account("도둑");
        long dogId = dog(owner, "보리");
        long walkId = walk(owner, dogId, 61, 10);

        saveCourse(thief, """
                {"walkId":%d,"name":"남의 길"}
                """.formatted(walkId))
                .andExpect(status().isNotFound());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 동쪽으로 {@code stepM}m 씩 {@code count} 개. 위도 37.5 에서 경도 1도는 약 88,000m 다. */
    private static String pathJson(int count, double stepM) {
        double stepLng = stepM / 88_000.0;
        List<String> points = new ArrayList<>(count);
        for (int i = 0; i < count; i++) {
            points.add("[%.7f,37.5445]".formatted(127.0400 + stepLng * i));
        }
        return "[" + String.join(",", points) + "]";
    }

    private long walk(Account account, long dogId, int points, double stepM) throws Exception {
        String json = """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","endedAt":"%s",
                 "distanceM":%d,"durationS":900,"path":%s}
                """.formatted(dogId, UUID.randomUUID(),
                Instant.now().minusSeconds(3600), Instant.now().minusSeconds(2700),
                (int) (points * stepM), pathJson(points, stepM));
        return body(save(account, json).andExpect(status().isCreated())).path("id").asLong();
    }

    private ResultActions save(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/walks")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions saveCourse(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/courses")
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

    private static List<Long> idsOf(JsonNode array) {
        List<Long> ids = new ArrayList<>();
        array.forEach(item -> ids.add(item.path("id").asLong()));
        return ids;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("course-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
