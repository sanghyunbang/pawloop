package com.heattrip.heat_trip_backend.schedule;

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

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 일정표를 <b>HTTP 로</b> 확인한다 — 이슈 #418 완료 조건 전부.
 *
 * <h2>왜 통합 테스트여야 하는가</h2>
 * <p>이 이슈에서 틀리면 사람이 다치는 것은 <b>인가</b>와 <b>충돌</b> 둘이다.
 *
 * <p>인가는 "판정 + 조회 필터 + 전역 예외 처리기의 상태 코드" 셋이 함께 맞아야 성립한다.
 * 서비스만 목으로 부르면 셋 중 하나가 빠져도 초록불이 난다 —
 * {@code ResponseStatusException(404)} 은 전역 처리기에 분기가 없으면 <b>500</b> 으로
 * 나가고, 그건 서비스 단위 테스트에서 정의상 안 보인다({@code CareSharingIntegrationTest}
 * 가 같은 이유를 적어 뒀다).
 *
 * <p>충돌은 <b>커밋된 값</b>을 다른 요청이 읽어야 성립한다. 그래서 {@code @Transactional}
 * 을 안 붙인다 — 붙이면 커밋되지 않은 것을 같은 트랜잭션 안에서 보게 되고,
 * {@code @Version} 이 올라가는 것을 못 본다.
 *
 * <p>애너테이션이 두 줄뿐인 것은 의도다 — {@code CareSharingIntegrationTest} 와 글자 그대로
 * 같아야 스프링 컨텍스트 캐시를 공유한다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
class ScheduleIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    // ─────────────────── 만들고 · 받고 · 고치고 · 지운다 ───────────────────

    @Test
    @DisplayName("아이 일정을 만들면 기간 조회에 그대로 나오고, 고치고, 지울 수 있다")
    void createsReadsUpdatesAndDeletes() throws Exception {
        Account mom = account("보리엄마");
        long dogId = dog(mom, "보리");

        JsonNode created = body(create(mom, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"vet",
                 "title":"보리 병원","memo":"광견병 접종","onDate":"2026-10-03","atTime":"10:30"}
                """.formatted(dogId, dogId)).andExpect(status().isCreated()));

        assertThat(created.path("status").asText())
                .as("새 일정은 planned 다 — 만들자마자 완료면 달력이 할 일을 안 보여 준다")
                .isEqualTo("planned");
        assertThat(created.path("version").asInt())
                .as("고치려면 이 값이 필요하다. 응답에 없으면 앱이 잠금을 쓸 수 없다")
                .isZero();
        assertThat(created.path("atTime").asText()).isEqualTo("10:30:00");

        long scheduleId = created.path("id").asLong();

        JsonNode listed = range(mom, "2026-10-01", "2026-10-31", null);
        assertThat(listed.size()).isEqualTo(1);
        assertThat(listed.get(0).path("title").asText()).isEqualTo("보리 병원");
        assertThat(listed.get(0).path("dogId").asLong()).isEqualTo(dogId);

        JsonNode edited = body(update(mom, scheduleId, 0, """
                {"kind":"vet","title":"보리 병원(오후로)","memo":"광견병 접종",
                 "onDate":"2026-10-03","atTime":"15:00","dogId":%d}
                """.formatted(dogId)).andExpect(status().isOk()));

        assertThat(edited.path("title").asText()).isEqualTo("보리 병원(오후로)");
        assertThat(edited.path("atTime").asText()).isEqualTo("15:00:00");
        assertThat(edited.path("version").asInt())
                .as("고치면 버전이 올라야 한다. 안 오르면 두 번째 편집이 첫 번째를 조용히 덮는다")
                .isEqualTo(1);
        assertThat(edited.path("updatedBy").path("userId").asLong())
                .as("누가 고쳤는지가 없으면 화면이 '○○님이 방금 고쳤어요' 를 못 그린다")
                .isEqualTo(mom.id());

        mockMvc.perform(delete("/api/schedules/{id}", scheduleId)
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isNoContent());

        assertThat(range(mom, "2026-10-01", "2026-10-31", null).size())
                .as("지웠으면 다음 조회에 없어야 한다")
                .isZero();
    }

    @Test
    @DisplayName("시각 없는 일정이 들어가고 atTime 이 null 로 온다 — 00:00 으로 채우면 안 된다")
    void keepsAnAllDayScheduleWithoutATime() throws Exception {
        Account mom = account("초코엄마");
        long dogId = dog(mom, "초코");

        JsonNode created = body(create(mom, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"bath",
                 "title":"이번 주말 목욕","onDate":"2026-10-04"}
                """.formatted(dogId, dogId)).andExpect(status().isCreated()));

        assertThat(created.path("atTime").isNull())
                .as("""
                        0시로 채우면 화면이 "00:00 목욕" 이라고 적게 되고, 그건 사용자가 \
                        안 정한 것을 정한 것처럼 보이게 한다.""")
                .isTrue();
    }

    // ─────────────────── 남의 것은 404 다 ───────────────────

    @Test
    @DisplayName("남의 아이 일정은 만들 수도 볼 수도 고칠 수도 없다 — 전부 404 다")
    void anotherPersonsDogIsAlways404() throws Exception {
        Account mom = account("보리엄마2");
        Account stranger = account("남");
        long dogId = dog(mom, "보리");
        long scheduleId = body(create(mom, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"med",
                 "title":"심장사상충","onDate":"2026-10-01"}
                """.formatted(dogId, dogId)).andExpect(status().isCreated())).path("id").asLong();

        create(stranger, """
                {"ownerKind":"dog","ownerRef":%d,"kind":"vet","title":"몰래","onDate":"2026-10-02"}
                """.formatted(dogId))
                .andExpect(status().isNotFound());

        mockMvc.perform(get("/api/schedules")
                        .param("from", "2026-10-01").param("to", "2026-10-31")
                        .param("ownerKind", "dog").param("ownerRef", String.valueOf(dogId))
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isNotFound());

        update(stranger, scheduleId, 0, "{\"title\":\"바꿔치기\"}")
                .andExpect(status().isNotFound());

        mockMvc.perform(delete("/api/schedules/{id}", scheduleId)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isNotFound());

        assertThat(range(mom, "2026-10-01", "2026-10-31", null).size())
                .as("남이 두드리는 동안 주인의 일정은 그대로여야 한다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("없는 일정도 남의 일정과 같은 404 다 — 403 이면 그 id 가 있다는 것을 알려 준다")
    void aMissingScheduleLooksTheSameAsSomeoneElses() throws Exception {
        Account nobody = account("아무나");

        mockMvc.perform(delete("/api/schedules/{id}", 999_999_999L)
                        .header("Authorization", "Bearer " + nobody.token()))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error.code").value("NOT_FOUND"));
    }

    @Test
    @DisplayName("안 든 가족 그룹의 일정은 404 다")
    void anotherFamilyIs404() throws Exception {
        Account dad = account("아빠A");
        Account outsider = account("바깥사람");
        long groupId = family(dad, "보리네 가족");

        create(outsider, """
                {"ownerKind":"group","ownerRef":%d,"kind":"etc","title":"몰래","onDate":"2026-10-02"}
                """.formatted(groupId))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("토큰이 없으면 401 이다")
    void requiresAToken() throws Exception {
        mockMvc.perform(get("/api/schedules").param("from", "2026-10-01").param("to", "2026-10-31"))
                .andExpect(status().isUnauthorized());
    }

    // ─────────────────── 둘이 고치면 뒤에 온 쪽이 409 ───────────────────

    @Test
    @DisplayName("같은 일정을 둘이 고치면 뒤에 온 쪽이 409 를 받고 응답에 최신 값이 있다")
    void theSecondEditorGetsAConflictWithTheCurrentValue() throws Exception {
        Account dad = account("아빠B");
        Account mom = account("엄마B");
        long groupId = family(dad, "보리네 가족", mom);

        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"토요일 병원",
                 "onDate":"2026-10-03","atTime":"10:00"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        // 아빠가 먼저 시각을 옮긴다. 엄마의 화면은 아직 version 0 을 들고 있다.
        update(dad, scheduleId, 0, """
                {"title":"토요일 병원","onDate":"2026-10-03","atTime":"14:00"}
                """).andExpect(status().isOk());

        JsonNode conflict = body(update(mom, scheduleId, 0, """
                {"title":"토요일 병원","onDate":"2026-10-03","atTime":"09:00"}
                """).andExpect(status().isConflict()));

        assertThat(conflict.path("error").path("code").asText())
                .as("앱의 공통 오류 처리가 error.code 로 분기한다 — 봉투를 깨면 이 응답만 못 읽는다")
                .isEqualTo("CONFLICT");
        assertThat(conflict.path("current").path("atTime").asText())
                .as("""
                        최신 값이 없으면 화면이 한 번 더 물어야 하고 그 사이에 또 바뀔 수 있다.""")
                .isEqualTo("14:00:00");
        assertThat(conflict.path("current").path("version").asInt()).isEqualTo(1);

        JsonNode still = range(dad, "2026-10-01", "2026-10-31", null);
        assertThat(still.get(0).path("atTime").asText())
                .as("""
                        뒤에 온 편집이 조용히 덮으면 아빠가 옮긴 병원 시각이 엄마의 옛 화면으로 \
                        되돌아간다. 그게 이 잠금이 막는 것이다.""")
                .isEqualTo("14:00:00");
    }

    // ─────────────────── 세 주인이 한 표에 산다 ───────────────────

    @Test
    @DisplayName("아이 것과 가족 것을 한 번에 물으면 한 목록으로, 날짜순으로 온다")
    void mergesDogAndGroupIntoOneList() throws Exception {
        Account dad = account("아빠C");
        long groupId = family(dad, "초코네 가족");
        long dogId = dog(dad, "초코");

        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"토요일 병원",
                 "onDate":"2026-11-07","atTime":"10:00"}
                """.formatted(groupId)).andExpect(status().isCreated());
        create(dad, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"med","title":"심장사상충",
                 "onDate":"2026-11-01"}
                """.formatted(dogId, dogId)).andExpect(status().isCreated());
        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"food","title":"사료 주문",
                 "onDate":"2026-11-07","atTime":"09:00"}
                """.formatted(groupId)).andExpect(status().isCreated());

        JsonNode merged = range(dad, "2026-11-01", "2026-11-30", null);

        assertThat(titles(merged))
                .as("""
                        주인을 안 주면 내가 볼 수 있는 전부가 온다. 두 목록을 이어 붙이면 \
                        순서가 종류순이 되므로 날짜 → 시각으로 다시 세운다.""")
                .containsExactly("심장사상충", "사료 주문", "토요일 병원");
    }

    @Test
    @DisplayName("dogId 로 거르면 가족 소유라도 그 아이 것만 온다 — \"우리 가족 일정 중 보리 것\"")
    void filtersByDogAcrossOwners() throws Exception {
        Account dad = account("아빠D");
        long groupId = family(dad, "보리초코네");
        long bori = dog(dad, "보리");
        long choco = dog(dad, "초코");

        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"dogId":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-12-05"}
                """.formatted(groupId, bori)).andExpect(status().isCreated());
        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"dogId":%d,"kind":"vet","title":"초코 병원",
                 "onDate":"2026-12-06"}
                """.formatted(groupId, choco)).andExpect(status().isCreated());
        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"food","title":"사료 주문",
                 "onDate":"2026-12-07"}
                """.formatted(groupId)).andExpect(status().isCreated());

        assertThat(titles(range(dad, "2026-12-01", "2026-12-31", bori)))
                .as("아이에 안 묶인 일정(\"사료 주문\")은 아이 필터에 안 걸린다")
                .containsExactly("보리 병원");
    }

    @Test
    @DisplayName("크루(room) 일정은 아직 400 이다 — 값만 열어 두고 멤버십은 #417 이 만든다")
    void rejectsCrewSchedulesForNow() throws Exception {
        Account someone = account("크루원");

        create(someone, """
                {"ownerKind":"room","ownerRef":1,"kind":"walk","title":"합동 산책",
                 "onDate":"2026-10-10"}
                """).andExpect(status().isBadRequest());
    }

    // ─────────────────── 담당자 ───────────────────

    @Test
    @DisplayName("가족 구성원을 담당으로 적을 수 있고, 응답에 이름이 함께 온다")
    void assignsAFamilyMember() throws Exception {
        Account dad = account("아빠E");
        Account mom = account("엄마E");
        long groupId = family(dad, "보리네 가족", mom);

        JsonNode created = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"토요일 병원",
                 "onDate":"2026-10-03","assignee":%d}
                """.formatted(groupId, mom.id())).andExpect(status().isCreated()));

        assertThat(created.path("assignee").path("nickname").asText())
                .as("id 만 주면 목록마다 이름을 한 번 더 물어야 한다")
                .isEqualTo("엄마E");
    }

    @Test
    @DisplayName("그 그룹을 못 보는 사람은 담당으로 못 적는다 — 남의 화면에 모르는 일정이 뜨면 안 된다")
    void refusesAnOutsiderAsAssignee() throws Exception {
        Account dad = account("아빠F");
        Account outsider = account("바깥사람F");
        long groupId = family(dad, "보리네 가족");

        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"토요일 병원",
                 "onDate":"2026-10-03","assignee":%d}
                """.formatted(groupId, outsider.id()))
                .andExpect(status().isNotFound());
    }

    // ─────────────────── 상태 ───────────────────

    @Test
    @DisplayName("완료로 바꾸면 doneAt 이 찍히고, planned 로 되돌리면 지워진다")
    void marksDoneAndBack() throws Exception {
        Account mom = account("엄마G");
        long dogId = dog(mom, "보리");
        long scheduleId = body(create(mom, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"walk","title":"저녁 산책",
                 "onDate":"2026-10-03"}
                """.formatted(dogId, dogId)).andExpect(status().isCreated())).path("id").asLong();

        JsonNode done = body(update(mom, scheduleId, 0,
                "{\"title\":\"저녁 산책\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk()));
        assertThat(done.path("status").asText()).isEqualTo("done");
        assertThat(done.path("doneAt").isNull()).isFalse();

        JsonNode back = body(update(mom, scheduleId, 1,
                "{\"title\":\"저녁 산책\",\"onDate\":\"2026-10-03\",\"status\":\"planned\"}")
                .andExpect(status().isOk()));
        assertThat(back.path("doneAt").isNull())
                .as("""
                        "아직 안 한 일" 에 완료 시각이 붙어 있으면 그 값을 읽는 화면이 \
                        언젠가 그것을 그린다.""")
                .isTrue();
    }

    // ─────────────────── 기간 ───────────────────

    @Test
    @DisplayName("기간이 92일을 넘으면 400 이다 — 한 요청이 몇 년치를 끌어오면 안 된다")
    void refusesTooWideARange() throws Exception {
        Account mom = account("엄마H");

        mockMvc.perform(get("/api/schedules")
                        .param("from", "2026-01-01").param("to", "2026-12-31")
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("VALIDATION"));

        mockMvc.perform(get("/api/schedules")
                        .param("from", "2026-04-01").param("to", "2026-03-01")
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isBadRequest());

        mockMvc.perform(get("/api/schedules")
                        .param("from", "2026-01-01").param("to", "2026-04-03")
                        .header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isOk());
    }

    // ─────────────────── 좌표가 없다 (A안 #235) ───────────────────

    @Test
    @DisplayName("요청에 좌표를 실어 보내도 저장되지 않고 응답에도 없다")
    void neverCarriesCoordinates() throws Exception {
        Account mom = account("엄마I");
        long dogId = dog(mom, "보리");

        String raw = create(mom, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"walk","title":"저녁 산책",
                 "onDate":"2026-10-03","lat":37.5665,"lng":126.9780}
                """.formatted(dogId, dogId))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        assertThat(raw)
                .as("""
                        A안(#235)에서 좌표는 기기를 안 떠난다. 일정에 위치 컬럼이 없으므로 \
                        보내도 조용히 버려지고, 응답에 그 이름이 나타나면 안 된다.""")
                .doesNotContain("lat").doesNotContain("lng");
    }

    // ─────────────────── 지그 ───────────────────

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("schedule-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private long dog(Account account, String name) throws Exception {
        return body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + account.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\",\"size\":\"small\"}".formatted(name)))
                .andExpect(status().isCreated()))
                .path("id").asLong();
    }

    private long family(Account owner, String name) throws Exception {
        return family(owner, name, null);
    }

    private long family(Account owner, String name, Account joiner) throws Exception {
        JsonNode created = body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\"}".formatted(name)))
                .andExpect(status().isCreated()));
        if (joiner != null) {
            long roomId = created.path("roomId").asLong();
            String code = body(mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                            .header("Authorization", "Bearer " + owner.token()))
                    .andExpect(status().isCreated()))
                    .path("code").asText();
            mockMvc.perform(post("/api/chat/invites/{code}/join", code)
                            .header("Authorization", "Bearer " + joiner.token()))
                    .andExpect(status().isOk());
        }
        return created.path("id").asLong();
    }

    private ResultActions create(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/schedules")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    /**
     * {@code version} 은 <b>쿼리</b>다 — 부분 수정 본문에는 필수 필드를 둘 수 없다
     * (ADR-0017 규약 4, {@code ContractConventionsTest}).
     */
    private ResultActions update(Account account, long scheduleId, int version, String json)
            throws Exception {
        return mockMvc.perform(patch("/api/schedules/{id}", scheduleId)
                .param("version", String.valueOf(version))
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private JsonNode range(Account account, String from, String to, Long dogId) throws Exception {
        var request = get("/api/schedules")
                .param("from", from).param("to", to)
                .header("Authorization", "Bearer " + account.token());
        if (dogId != null) {
            request = request.param("dogId", String.valueOf(dogId));
        }
        return body(mockMvc.perform(request).andExpect(status().isOk()));
    }

    private static List<String> titles(JsonNode array) {
        List<String> out = new ArrayList<>();
        array.forEach(node -> out.add(node.path("title").asText()));
        return out;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(
                actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }
}
