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

    /** 가족을 나가는 것은 방을 나가는 것이다(ADR-0011). */
    @Autowired
    private com.heattrip.heat_trip_backend.chat.ChatRoomService chatRooms;

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
    @DisplayName("아빠가 엄마 아이 보리의 일정을 적고, 둘 다 그 일정을 본다 (#563)")
    void aHouseholdDogCanBeScheduledByAnyoneInTheHouse() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        family(mom, "보리네", dad);

        create(dad, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"vet",
                 "title":"보리 검진","onDate":"2026-10-03"}
                """.formatted(bori, bori))
                .andExpect(status().isCreated());

        assertThat(titles(range(dad, "2026-10-01", "2026-10-31", null)))
                .as("화면이 보리를 고를 수 있다고 해 놓고 저장에서 404 면 그게 가장 나쁜 모양이다")
                .contains("보리 검진");
        assertThat(titles(range(mom, "2026-10-01", "2026-10-31", null)))
                .as("엄마도 본다 — 안 보이면 병원에 두 번 전화한다")
                .contains("보리 검진");
    }

    @Test
    @DisplayName("가족을 나가면 그 집 아이 일정이 안 보인다 (#563)")
    void leavingTheHouseholdHidesItsDogSchedules() throws Exception {
        Account mom = account("엄마");
        Account dad = account("아빠");
        long bori = dog(mom, "보리");
        long roomId = familyRoom(mom, "보리네", dad);

        create(dad, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"vet",
                 "title":"보리 검진","onDate":"2026-10-03"}
                """.formatted(bori, bori))
                .andExpect(status().isCreated());
        assertThat(titles(range(dad, "2026-10-01", "2026-10-31", null))).contains("보리 검진");

        chatRooms.leaveRoom(roomId, dad.id());

        assertThat(titles(range(dad, "2026-10-01", "2026-10-31", null)))
                .as("보리는 이제 아빠 집 아이가 아니다. 일정은 사라지지 않고 엄마에게 남는다")
                .doesNotContain("보리 검진");
        assertThat(titles(range(mom, "2026-10-01", "2026-10-31", null))).contains("보리 검진");
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
    @DisplayName("안 든 크루의 일정은 404 다 — 남의 아이·안 든 그룹과 같은 답이다")
    void crewSchedulesNeedMembership() throws Exception {
        Account someone = account("크루원");

        // 없는 크루도, 안 든 크루도 같은 404 다 — 403 을 주면 "그 id 는 존재한다" 가 샌다.
        // 크루 멤버가 실제로 만드는 경로는 CrewFavorIntegrationTest 가 끝까지 걸어 본다
        // (품앗이를 맡으면 owner_kind=room 한 줄이 생기고 그것이 달력에 뜬다, #417).
        create(someone, """
                {"ownerKind":"room","ownerRef":999999,"kind":"walk","title":"합동 산책",
                 "onDate":"2026-10-10"}
                """).andExpect(status().isNotFound());
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


    // ─────────────────── 완료하면 케어 기록이 함께 남는다 (#420) ───────────────────

    @Test
    @DisplayName("가족 일정을 완료로 바꾸면 오늘의 케어에 한 줄이 생긴다 — 같은 일을 두 번 안 적게, 아이까지")
    void markingDoneWritesACareLog() throws Exception {
        Account dad = account("아빠J");
        long groupId = family(dad, "보리네 가족");
        long dogId = dog(dad, "보리");
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"dogId":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-10-03"}
                """.formatted(groupId, dogId)).andExpect(status().isCreated())).path("id").asLong();

        // 앱은 PATCH 에 아이를 늘 같이 보낸다 — 빼면 "아이 없음" 으로 고치는 것이 된다.
        update(dad, scheduleId, 0, """
                {"title":"보리 병원","onDate":"2026-10-03","dogId":%d,"status":"done"}
                """.formatted(dogId))
                .andExpect(status().isOk());

        JsonNode logs = careLogs(dad, groupId);
        assertThat(logs.size()).isEqualTo(1);
        assertThat(logs.get(0).path("type").asText()).isEqualTo("vet");
        assertThat(logs.get(0).path("doneBy").path("userId").asLong())
                .as("수행자는 담당자가 아니라 **실제로 누른 사람**이다 — care_log 가 이미 그 규칙이다")
                .isEqualTo(dad.id());
        assertThat(logs.get(0).path("dogId").asLong())
                .as("일정의 아이가 기록에도 붙는다(#743) — 안 붙으면 날짜별 화면이 '아이 안 정함' 으로 본다")
                .isEqualTo(dogId);
    }

    @Test
    @DisplayName("아이가 없는 가족 일정을 완료하면 기록의 아이도 비어 있다 — 가족 공통은 그대로")
    void markingDoneWithoutDogLeavesTheLogWithoutDog() throws Exception {
        Account dad = account("아빠K");
        long groupId = family(dad, "보리네 가족");
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"walk","title":"가족 산책",
                 "onDate":"2026-10-03"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        update(dad, scheduleId, 0,
                "{\"title\":\"가족 산책\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk());

        JsonNode logs = careLogs(dad, groupId);
        assertThat(logs.size()).isEqualTo(1);
        assertThat(logs.get(0).path("dogId").isNull()).isTrue();
    }

    @Test
    @DisplayName("되돌리면 그 줄이 사라진다 — 취소한 일이 오늘의 케어에 남으면 안 된다")
    void revertingRemovesTheCareLog() throws Exception {
        Account dad = account("아빠K");
        long groupId = family(dad, "보리네 가족");
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"walk","title":"저녁 산책",
                 "onDate":"2026-10-03"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        update(dad, scheduleId, 0,
                "{\"title\":\"저녁 산책\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk());
        assertThat(careLogs(dad, groupId).size()).isEqualTo(1);

        update(dad, scheduleId, 1,
                "{\"title\":\"저녁 산책\",\"onDate\":\"2026-10-03\",\"status\":\"planned\"}")
                .andExpect(status().isOk());

        assertThat(careLogs(dad, groupId).size()).isZero();
    }

    @Test
    @DisplayName("건너뜀도 케어 기록을 안 남긴다 — 건너뛴 것은 한 것이 아니다")
    void skippingLeavesNoCareLog() throws Exception {
        Account dad = account("아빠L");
        long groupId = family(dad, "보리네 가족");
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"med","title":"심장사상충",
                 "onDate":"2026-10-03"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        update(dad, scheduleId, 0,
                "{\"title\":\"심장사상충\",\"onDate\":\"2026-10-03\",\"status\":\"skipped\"}")
                .andExpect(status().isOk());

        assertThat(careLogs(dad, groupId).size()).isZero();
    }

    @Test
    @DisplayName("완료한 뒤 건너뜀으로 바꾸면 남았던 줄을 거둔다")
    void movingFromDoneToSkippedWithdrawsTheLog() throws Exception {
        Account dad = account("아빠M");
        long groupId = family(dad, "보리네 가족");
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-10-03"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        update(dad, scheduleId, 0,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk());
        update(dad, scheduleId, 1,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"skipped\"}")
                .andExpect(status().isOk());

        assertThat(careLogs(dad, groupId).size()).isZero();
    }

    @Test
    @DisplayName("미용·목욕·사료·그 밖은 케어 기록을 안 남긴다 — 케어 종류가 아니다")
    void nonCareKindsWriteNothing() throws Exception {
        Account dad = account("아빠N");
        long groupId = family(dad, "보리네 가족");

        for (String kind : List.of("groom", "bath", "food", "etc")) {
            long id = body(create(dad, """
                    {"ownerKind":"group","ownerRef":%d,"kind":"%s","title":"%s 하기",
                     "onDate":"2026-10-03"}
                    """.formatted(groupId, kind, kind)).andExpect(status().isCreated()))
                    .path("id").asLong();
            update(dad, id, 0, """
                    {"title":"%s 하기","onDate":"2026-10-03","status":"done"}
                    """.formatted(kind)).andExpect(status().isOk());
        }

        assertThat(careLogs(dad, groupId).size())
                .as("care_log 의 CHECK 가 받는 일곱에 없는 값이다 — 억지로 넣으면 오늘의 케어가 "
                        + "물·밥·산책이 아닌 것으로 채워진다")
                .isZero();
    }

    @Test
    @DisplayName("아이 소유 일정은 케어 기록을 안 남긴다 — 넣을 그룹이 없다")
    void dogOwnedSchedulesWriteNoCareLog() throws Exception {
        Account mom = account("엄마O");
        long groupId = family(mom, "보리네 가족");
        long dogId = dog(mom, "보리");
        long scheduleId = body(create(mom, """
                {"ownerKind":"dog","ownerRef":%d,"dogId":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-10-03"}
                """.formatted(dogId, dogId)).andExpect(status().isCreated())).path("id").asLong();

        update(mom, scheduleId, 0,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk());

        assertThat(careLogs(mom, groupId).size()).isZero();
    }

    @Test
    @DisplayName("아빠가 완료한 것을 엄마가 되돌릴 수 있다 — 되돌릴 권한은 그 일정의 권한이다")
    void anotherMemberCanRevertAndTheLogGoes() throws Exception {
        Account dad = account("아빠P");
        Account mom = account("엄마P");
        long groupId = family(dad, "보리네 가족", mom);
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-10-03"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        update(dad, scheduleId, 0,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk());
        assertThat(careLogs(mom, groupId).size()).isEqualTo(1);

        // 케어 칸의 삭제는 "본인 기록만" 이지만, 되돌리기는 그 규칙을 안 본다 — 아빠가 찍은
        // 줄을 엄마가 거둘 수 있어야 한다(CareLogging.withdraw javadoc).
        update(mom, scheduleId, 1,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"planned\"}")
                .andExpect(status().isOk());

        assertThat(careLogs(mom, groupId).size()).isZero();
    }

    @Test
    @DisplayName("일정을 지워도 케어 기록은 남는다 — 계획을 정리하다 사실을 잃지 않는다")
    void deletingTheScheduleKeepsTheCareLog() throws Exception {
        Account dad = account("아빠Q");
        long groupId = family(dad, "보리네 가족");
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-10-03"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();
        update(dad, scheduleId, 0,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk());

        mockMvc.perform(delete("/api/schedules/{id}", scheduleId)
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNoContent());

        assertThat(careLogs(dad, groupId).size())
                .as("이미 다녀온 병원의 기록까지 사라지면, 계획을 정리하다 사실을 잃는다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("케어 칸에서 그 줄을 먼저 지워도 되돌리기가 실패하지 않는다")
    void revertingSurvivesAnAlreadyDeletedLog() throws Exception {
        Account dad = account("아빠R");
        long groupId = family(dad, "보리네 가족");
        long scheduleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-10-03"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();
        update(dad, scheduleId, 0,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"done\"}")
                .andExpect(status().isOk());

        long careLogId = careLogs(dad, groupId).get(0).path("id").asLong();
        mockMvc.perform(delete("/api/groups/{g}/care-logs/{c}", groupId, careLogId)
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNoContent());

        update(dad, scheduleId, 1,
                "{\"title\":\"보리 병원\",\"onDate\":\"2026-10-03\",\"status\":\"planned\"}")
                .andExpect(status().isOk());
    }


    // ─────────────────── 반복 (#421) ───────────────────

    @Test
    @DisplayName("매주 화요일 규칙 하나가 한 달 조회에서 네 줄로 펼쳐진다")
    void aWeeklyRuleExpandsAcrossTheMonth() throws Exception {
        Account dad = account("아빠S");
        long groupId = family(dad, "보리네 가족");
        // 2026-12-01 은 화요일. 12월의 화요일은 1·8·15·22·29 다섯이다.
        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"med","title":"심장사상충",
                 "onDate":"2026-12-01","repeatKind":"weekly"}
                """.formatted(groupId)).andExpect(status().isCreated());

        JsonNode listed = range(dad, "2026-12-01", "2026-12-31", null);

        assertThat(dates(listed)).containsExactly(
                "2026-12-01", "2026-12-08", "2026-12-15", "2026-12-22", "2026-12-29");
        assertThat(listed.get(0).path("occurrence").asBoolean())
                .as("펼친 하루에는 행이 없다 — 화면이 (id, onDate) 를 키로 삼아야 한다")
                .isTrue();
    }

    @Test
    @DisplayName("작년에 시작한 규칙도 이번 달 조회에 나온다 — on_date 만 보면 한 줄도 안 나온다")
    void aRuleThatStartedLongAgoStillShowsUp() throws Exception {
        Account dad = account("아빠T");
        long groupId = family(dad, "보리네 가족");
        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"med","title":"심장사상충",
                 "onDate":"2025-12-02","repeatKind":"monthly"}
                """.formatted(groupId)).andExpect(status().isCreated());

        JsonNode listed = range(dad, "2026-12-01", "2026-12-31", null);

        assertThat(dates(listed)).containsExactly("2026-12-02");
    }

    @Test
    @DisplayName("종료일 뒤로는 안 나온다")
    void nothingComesAfterTheEndDate() throws Exception {
        Account dad = account("아빠U");
        long groupId = family(dad, "보리네 가족");
        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"walk","title":"저녁 산책",
                 "onDate":"2026-12-01","repeatKind":"daily","repeatUntil":"2026-12-03"}
                """.formatted(groupId)).andExpect(status().isCreated());

        JsonNode listed = range(dad, "2026-12-01", "2026-12-31", null);

        assertThat(dates(listed))
                .containsExactly("2026-12-01", "2026-12-02", "2026-12-03");
    }

    @Test
    @DisplayName("31일 규칙은 30일까지인 달을 건너뛴다 — 사용자가 안 정한 날에 오면 안 된다")
    void aMonthlyRuleSkipsShortMonths() throws Exception {
        Account dad = account("아빠V");
        long groupId = family(dad, "보리네 가족");
        create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"food","title":"사료 주문",
                 "onDate":"2026-10-31","repeatKind":"monthly"}
                """.formatted(groupId)).andExpect(status().isCreated());

        assertThat(dates(range(dad, "2026-11-01", "2026-11-30", null)))
                .as("11월에는 31일이 없다")
                .isEmpty();
        assertThat(dates(range(dad, "2026-12-01", "2026-12-31", null)))
                .containsExactly("2026-12-31");
    }

    @Test
    @DisplayName("하루를 건너뛰면 그날만 빠지고 나머지는 그대로다")
    void skippingOneDayLeavesTheRest() throws Exception {
        Account dad = account("아빠W");
        long groupId = family(dad, "보리네 가족");
        long ruleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"bath","title":"목욕",
                 "onDate":"2026-12-01","repeatKind":"weekly"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(delete("/api/schedules/{id}", ruleId)
                        .param("date", "2026-12-15")
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNoContent());

        assertThat(dates(range(dad, "2026-12-01", "2026-12-31", null)))
                .as("\"이번 주만 안 함\" 이 반복을 지우는 일이 되면 안 된다")
                .containsExactly("2026-12-01", "2026-12-08", "2026-12-22", "2026-12-29");
    }

    @Test
    @DisplayName("하루만 고치면 그날만 바뀌고 규칙은 그대로다")
    void overridingOneDayLeavesTheRuleAlone() throws Exception {
        Account dad = account("아빠X");
        long groupId = family(dad, "보리네 가족");
        long ruleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"bath","title":"목욕",
                 "onDate":"2026-12-01","atTime":"10:00","repeatKind":"weekly"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        JsonNode moved = body(mockMvc.perform(patch("/api/schedules/{id}", ruleId)
                        .param("version", "0")
                        .param("date", "2026-12-15")
                        .header("Authorization", "Bearer " + dad.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"목욕(오후로)\",\"onDate\":\"2026-12-15\","
                                + "\"atTime\":\"15:00\"}"))
                .andExpect(status().isOk()));

        assertThat(moved.path("id").asLong())
                .as("옮긴 하루는 자기 행이다 — 규칙과 다른 id 여야 완료 표시가 그 하나에만 붙는다")
                .isNotEqualTo(ruleId);
        assertThat(moved.path("repeatKind").asText()).isEqualTo("none");

        JsonNode listed = range(dad, "2026-12-01", "2026-12-31", null);
        assertThat(dates(listed)).containsExactly(
                "2026-12-01", "2026-12-08", "2026-12-15", "2026-12-22", "2026-12-29");
        JsonNode fifteenth = listed.get(2);
        assertThat(fifteenth.path("title").asText()).isEqualTo("목욕(오후로)");
        assertThat(fifteenth.path("atTime").asText()).isEqualTo("15:00:00");
        assertThat(fifteenth.path("occurrence").asBoolean())
                .as("그날은 이제 진짜 행이다")
                .isFalse();
        assertThat(listed.get(0).path("title").asText())
                .as("규칙은 그대로다")
                .isEqualTo("목욕");
    }

    @Test
    @DisplayName("완료 표시는 그날 하나에만 붙는다 — 규칙 전체가 완료되지 않는다")
    void completingOneDayDoesNotCompleteTheRule() throws Exception {
        Account dad = account("아빠Y");
        long groupId = family(dad, "보리네 가족");
        long ruleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"med","title":"심장사상충",
                 "onDate":"2026-12-01","repeatKind":"weekly"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(patch("/api/schedules/{id}", ruleId)
                        .param("version", "0")
                        .param("date", "2026-12-08")
                        .header("Authorization", "Bearer " + dad.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"심장사상충\",\"onDate\":\"2026-12-08\","
                                + "\"status\":\"done\"}"))
                .andExpect(status().isOk());

        JsonNode listed = range(dad, "2026-12-01", "2026-12-31", null);
        assertThat(statuses(listed))
                .as("한 번 먹였다고 앞으로 오는 날이 전부 완료되면 안 된다")
                .containsExactly("planned", "done", "planned", "planned", "planned");
        assertThat(careLogs(dad, groupId).size())
                .as("그 하루가 진짜 행이 됐으므로 #420 의 연결도 그대로 걸린다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("규칙을 통째로 지우면 예외와 옮겨 둔 하루가 함께 사라진다")
    void deletingTheRuleTakesEverything() throws Exception {
        Account dad = account("아빠Z");
        long groupId = family(dad, "보리네 가족");
        long ruleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"bath","title":"목욕",
                 "onDate":"2026-12-01","repeatKind":"weekly"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();
        mockMvc.perform(patch("/api/schedules/{id}", ruleId)
                        .param("version", "0").param("date", "2026-12-15")
                        .header("Authorization", "Bearer " + dad.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"목욕(옮김)\",\"onDate\":\"2026-12-16\"}"))
                .andExpect(status().isOk());

        mockMvc.perform(delete("/api/schedules/{id}", ruleId)
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNoContent());

        assertThat(range(dad, "2026-12-01", "2026-12-31", null).size())
                .as("옮겨 둔 하루만 남으면 그것이 무엇의 하루였는지 아무도 모른다")
                .isZero();
    }

    @Test
    @DisplayName("규칙이 안 오는 날은 건너뛸 수도 고칠 수도 없다 — 404 다")
    void aDayTheRuleDoesNotComeIs404() throws Exception {
        Account dad = account("아빠AA");
        long groupId = family(dad, "보리네 가족");
        long ruleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"bath","title":"목욕",
                 "onDate":"2026-12-01","repeatKind":"weekly"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        // 12-02 는 수요일이라 이 규칙이 안 온다.
        mockMvc.perform(delete("/api/schedules/{id}", ruleId)
                        .param("date", "2026-12-02")
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("되풀이가 아닌 일정에는 하루 지정이 안 통한다 — 404 다")
    void aPlainScheduleHasNoOccurrences() throws Exception {
        Account dad = account("아빠AB");
        long groupId = family(dad, "보리네 가족");
        long id = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"vet","title":"보리 병원",
                 "onDate":"2026-12-01"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(delete("/api/schedules/{id}", id)
                        .param("date", "2026-12-01")
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("반복을 안 보내면 안 바뀐다 — 제목만 고쳤는데 반복이 사라지면 안 된다")
    void editingWithoutRepeatKeepsTheRule() throws Exception {
        Account dad = account("아빠AC");
        long groupId = family(dad, "보리네 가족");
        long ruleId = body(create(dad, """
                {"ownerKind":"group","ownerRef":%d,"kind":"bath","title":"목욕",
                 "onDate":"2026-12-01","repeatKind":"weekly"}
                """.formatted(groupId)).andExpect(status().isCreated())).path("id").asLong();

        JsonNode edited = body(update(dad, ruleId, 0,
                "{\"title\":\"목욕(이름만)\",\"onDate\":\"2026-12-01\"}")
                .andExpect(status().isOk()));

        assertThat(edited.path("repeatKind").asText()).isEqualTo("weekly");
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

    private JsonNode careLogs(Account account, long groupId) throws Exception {
        return body(mockMvc.perform(get("/api/groups/{groupId}/care-logs", groupId)
                        .header("Authorization", "Bearer " + account.token()))
                .andExpect(status().isOk()));
    }


    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("schedule-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
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

    /** 방 id 를 돌려준다 — 가족을 나가는 것은 방을 나가는 것이다(ADR-0011). */
    private long familyRoom(Account owner, String name, Account joiner) throws Exception {
        family(owner, name, joiner);
        return lastRoomId;
    }

    /** {@link #family} 가 만든 방 id. 나가기를 재는 테스트만 쓴다. */
    private long lastRoomId;

    private long family(Account owner, String name, Account joiner) throws Exception {
        JsonNode created = body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\"}".formatted(name)))
                .andExpect(status().isCreated()));
        lastRoomId = created.path("roomId").asLong();
        if (joiner != null) {
            long roomId = lastRoomId;
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

private static List<String> dates(JsonNode array) {
        List<String> out = new ArrayList<>();
        array.forEach(node -> out.add(node.path("onDate").asText()));
        return out;
    }

    private static List<String> statuses(JsonNode array) {
        List<String> out = new ArrayList<>();
        array.forEach(node -> out.add(node.path("status").asText()));
        return out;
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
