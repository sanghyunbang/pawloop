package com.heattrip.heat_trip_backend.crew;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavor;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavorSlot;
import com.heattrip.heat_trip_backend.crew.entity.CrewFavorStatus;
import com.heattrip.heat_trip_backend.crew.repository.CrewFavorRepository;
import com.heattrip.heat_trip_backend.crew.repository.CrewRepository;
import com.heattrip.heat_trip_backend.dog.entity.Dog;
import com.heattrip.heat_trip_backend.dog.repository.DogRepository;
import com.heattrip.heat_trip_backend.schedule.repository.ScheduleRepository;
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
import java.time.LocalDate;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 품앗이와, 방장 넘기기·크루 지우기를 <b>HTTP 로</b> 확인한다 — 이슈 #417.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>맡으면 달력에 한 줄이 남는가.</b> 그것이 이 기능의 알맹이다 — 크루 화면에만 두면
 * 그날 아침에 아무도 그것을 안 본다. 그리고 <b>무르면 그 줄이 사라지는가</b>. 안 사라지면
 * 아무도 안 하기로 한 일이 그날 아침에 뜬다.
 *
 * <p>그 줄은 {@code owner_kind=room} 이라 <b>크루 사람 모두의 달력</b>에 떠야 한다 —
 * {@code GET /api/schedules} 를 실제로 불러 잰다. 표를 직접 읽으면 "행은 있는데 조회에는
 * 안 나오는" 경우를 못 잡는다.
 *
 * <p>{@code @Transactional} 을 안 붙인다 — 크루 지우기가 방·부탁·일정을 함께 지우는지 보려면
 * 커밋된 상태를 봐야 한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CrewFavorIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    /** 성동구 왕십리2동. */
    private static final String SEONGDONG = "1120052000";

    /** 지나지 않은 날 — 지난 날짜로는 부탁할 수 없다. */
    private static final LocalDate SOON = LocalDate.now().plusDays(14);

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private DogRepository dogRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Autowired
    private CrewRepository crewRepository;

    @Autowired
    private CrewFavorRepository favorRepository;

    @Autowired
    private ScheduleRepository scheduleRepository;

    // ───────────── 완료 조건 5 — 맡으면 크루 일정에 한 줄 ─────────────

    @Test
    @DisplayName("품앗이를 맡으면 크루 일정 한 줄이 생기고 크루 사람 모두의 달력에 뜬다")
    void takingAFavorLeavesALineOnEveryonesCalendar() throws Exception {
        Account asker = accountIn("부탁하는사람", SEONGDONG);
        Account taker = account("맡는사람");
        long dogId = dogOf(asker, "보리");

        Crew crew = crewWith(asker, taker);
        JsonNode favor = postFavor(asker, crew.id(), dogId, "두 시간만 부탁드려요");

        assertThat(favor.path("status").asText()).isEqualTo("open");
        assertThat(favor.path("scheduleId").isNull()).isTrue();

        JsonNode taken = body(take(taker, crew.id(), favor.path("id").asLong())
                .andExpect(status().isOk()));

        assertThat(taken.path("status").asText()).isEqualTo("taken");
        assertThat(taken.path("takenBy").path("nickname").asText()).isEqualTo("맡는사람");
        long scheduleId = taken.path("scheduleId").asLong();
        assertThat(scheduleId).as("맡은 약속은 달력에 있어야 한다").isPositive();

        // 맡은 사람의 달력.
        JsonNode mine = body(calendar(taker).andExpect(status().isOk()));
        assertThat(idsOf(mine)).contains(scheduleId);

        // 부탁한 사람의 달력에도 — 크루 소유라 둘 다 본다.
        assertThat(idsOf(body(calendar(asker).andExpect(status().isOk()))))
                .as("""
                        owner_kind=room 은 그 크루 사람 모두의 것이다. 맡은 사람만 보면 \
                        부탁한 사람은 누가 오는지 달력에서 확인할 수 없다.""")
                .contains(scheduleId);

        JsonNode line = lineOf(mine, scheduleId);
        assertThat(line.path("ownerKind").asText()).isEqualTo("room");
        assertThat(line.path("ownerRef").asLong()).isEqualTo(crew.id());
        assertThat(line.path("title").asText()).isEqualTo("보리 봐 주기");
        assertThat(line.path("memo").asText())
                .as("시간대는 메모로 간다 — at_time 을 0시로 채우면 달력이 새벽 12시로 그린다")
                .isEqualTo("오후 · 두 시간만 부탁드려요");
        assertThat(line.path("atTime").isNull()).isTrue();
        assertThat(line.path("assignee").path("userId").asLong()).isEqualTo(taker.id());
    }

    @Test
    @DisplayName("무르면 달력의 줄이 사라지고 부탁이 다시 열린다")
    void releasingTakesTheLineBack() throws Exception {
        Account asker = accountIn("부탁하는사람", SEONGDONG);
        Account taker = account("맡는사람");
        Crew crew = crewWith(asker, taker);

        long favorId = postFavor(asker, crew.id(), null, null).path("id").asLong();
        long scheduleId = body(take(taker, crew.id(), favorId).andExpect(status().isOk()))
                .path("scheduleId").asLong();

        JsonNode released = body(mockMvc.perform(
                        delete("/api/crews/{c}/favors/{f}/take", crew.id(), favorId)
                                .header("Authorization", "Bearer " + taker.token()))
                .andExpect(status().isOk()));

        assertThat(released.path("status").asText()).isEqualTo("open");
        assertThat(released.path("takenBy").isNull()).isTrue();
        assertThat(scheduleRepository.findById(scheduleId))
                .as("아무도 안 하기로 한 일이 그날 아침에 뜨면 안 된다")
                .isEmpty();
    }

    @Test
    @DisplayName("아이를 안 고른 부탁의 달력 제목은 '품앗이' 다")
    void aFavorWithoutADogStillReadsOnTheCalendar() throws Exception {
        Account asker = accountIn("아이없는사람", SEONGDONG);
        Account taker = account("맡는사람");
        Crew crew = crewWith(asker, taker);

        long favorId = postFavor(asker, crew.id(), null, null).path("id").asLong();
        long scheduleId = body(take(taker, crew.id(), favorId).andExpect(status().isOk()))
                .path("scheduleId").asLong();

        JsonNode line = lineOf(body(calendar(taker).andExpect(status().isOk())), scheduleId);
        assertThat(line.path("title").asText()).isEqualTo("품앗이");
        assertThat(line.path("memo").asText()).isEqualTo("오후");
    }

    // ───────────── 맡기의 규칙 ─────────────

    @Test
    @DisplayName("이미 맡은 부탁은 409 다 — 둘이 오면 부탁한 사람은 누가 오는지 모른다")
    void aFavorCanOnlyBeTakenOnce() throws Exception {
        Account asker = accountIn("부탁하는사람", SEONGDONG);
        Account first = account("먼저맡은사람");
        Account second = account("나중사람");
        Crew crew = crewWith(asker, first, second);

        long favorId = postFavor(asker, crew.id(), null, null).path("id").asLong();
        take(first, crew.id(), favorId).andExpect(status().isOk());

        take(second, crew.id(), favorId).andExpect(status().isConflict());
    }

    @Test
    @DisplayName("내가 올린 부탁은 내가 못 맡는다")
    void theAskerCannotTakeTheirOwnFavor() throws Exception {
        Account asker = accountIn("혼잣말하는사람", SEONGDONG);
        Account other = account("다른사람");
        Crew crew = crewWith(asker, other);

        long favorId = postFavor(asker, crew.id(), null, null).path("id").asLong();

        take(asker, crew.id(), favorId).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("맡은 사람만 무르고, 올린 사람만 지운다")
    void releasingAndCancellingHaveDifferentOwners() throws Exception {
        Account asker = accountIn("부탁하는사람", SEONGDONG);
        Account taker = account("맡는사람");
        Crew crew = crewWith(asker, taker);

        long favorId = postFavor(asker, crew.id(), null, null).path("id").asLong();
        long scheduleId = body(take(taker, crew.id(), favorId).andExpect(status().isOk()))
                .path("scheduleId").asLong();

        // 올린 사람은 무르지 못한다 — 그건 맡은 사람의 동작이다.
        mockMvc.perform(delete("/api/crews/{c}/favors/{f}/take", crew.id(), favorId)
                        .header("Authorization", "Bearer " + asker.token()))
                .andExpect(status().isForbidden());

        // 맡은 사람은 지우지 못한다 — 그건 올린 사람의 동작이다.
        mockMvc.perform(delete("/api/crews/{c}/favors/{f}", crew.id(), favorId)
                        .header("Authorization", "Bearer " + taker.token()))
                .andExpect(status().isForbidden());

        // 올린 사람이 거둬들이면 부탁도 달력 줄도 사라진다.
        mockMvc.perform(delete("/api/crews/{c}/favors/{f}", crew.id(), favorId)
                        .header("Authorization", "Bearer " + asker.token()))
                .andExpect(status().isNoContent());

        assertThat(favorRepository.findById(favorId)).isEmpty();
        assertThat(scheduleRepository.findById(scheduleId)).isEmpty();
    }

    @Test
    @DisplayName("아무도 안 맡은 부탁은 무를 수 없다 — 403, 그리고 부탁은 그대로 열려 있다")
    void aFavorNobodyTookCannotBeReleased() throws Exception {
        Account asker = accountIn("부탁하는사람", SEONGDONG);
        Account member = account("구경하는사람");
        Crew crew = crewWith(asker, member);
        long favorId = postFavor(asker, crew.id(), null, null).path("id").asLong();

        // takenBy 가 null 인 자리다 — 그 null 을 안 보면 여기서 500 이 나간다(#510).
        mockMvc.perform(delete("/api/crews/{c}/favors/{f}/take", crew.id(), favorId)
                        .header("Authorization", "Bearer " + member.token()))
                .andExpect(status().isForbidden());

        assertThat(favorRepository.findById(favorId).orElseThrow().getStatus())
                .as("무르기가 실패했으면 부탁은 열린 채로 남아 다른 사람이 맡을 수 있어야 한다")
                .isEqualTo(CrewFavorStatus.OPEN);
    }

    @Test
    @DisplayName("남의 아이로는 부탁할 수 없고, 지난 날짜로도 못 한다")
    void aFavorNeedsMyOwnDogAndAFutureDate() throws Exception {
        Account asker = accountIn("부탁하는사람", SEONGDONG);
        Account other = account("남");
        Crew crew = crewWith(asker, other);
        long othersDog = dogOf(other, "남의보리");

        mockMvc.perform(post("/api/crews/{c}/favors", crew.id())
                        .header("Authorization", "Bearer " + asker.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"onDate":"%s","slot":"afternoon","dogId":%d}"""
                                .formatted(SOON, othersDog)))
                .andExpect(status().isNotFound());

        mockMvc.perform(post("/api/crews/{c}/favors", crew.id())
                        .header("Authorization", "Bearer " + asker.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"onDate":"%s","slot":"afternoon"}"""
                                .formatted(LocalDate.now().minusDays(1))))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("우리 집 아이로는 부탁할 수 있다 — 아빠가 엄마의 보리 산책을 부탁한다 (#563)")
    void aHouseholdDogCanBeAskedFor() throws Exception {
        Account dad = accountIn("아빠", SEONGDONG);
        Account mom = account("엄마");
        Account neighbour = account("이웃");
        long bori = dogOf(mom, "보리");
        joinFamily(mom, dad);

        Crew crew = crewWith(dad, neighbour);
        JsonNode favor = postFavor(dad, crew.id(), bori, "두 시간만 부탁드려요");

        assertThat(favor.path("dog").path("dogId").asLong())
                .as("부탁 시트가 집 아이를 보여 준다 — 거기서 고른 보리가 404 면 안 된다")
                .isEqualTo(bori);
    }

    @Test
    @DisplayName("크루에 안 든 사람은 부탁을 보지도 올리지도 못한다 — 공개 크루라도 404")
    void favorsAreForMembersOnly() throws Exception {
        Account owner = accountIn("방장", SEONGDONG);
        Account outsider = accountIn("구경꾼", SEONGDONG);
        Crew crew = crewWith(owner);

        mockMvc.perform(get("/api/crews/{c}/favors", crew.id())
                        .header("Authorization", "Bearer " + outsider.token()))
                .andExpect(status().isNotFound());

        mockMvc.perform(post("/api/crews/{c}/favors", crew.id())
                        .header("Authorization", "Bearer " + outsider.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"onDate":"%s","slot":"morning"}""".formatted(SOON)))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("지난 부탁은 목록에서 빠진다 — 아무도 못 맡는 카드가 위를 막지 않는다")
    void pastFavorsDropOutOfTheList() throws Exception {
        Account asker = accountIn("부탁하는사람", SEONGDONG);
        Account other = account("다른사람");
        Crew crew = crewWith(asker, other);

        long upcoming = postFavor(asker, crew.id(), null, "다음 주").path("id").asLong();

        // 지난 부탁은 API 로 못 만든다(400) — 표에 직접 넣어 **목록만** 잰다. 이 줄이 없으면
        // 이 검사는 "빠지는가" 가 아니라 "하나 있는가" 만 재게 된다.
        long past = favorRepository.save(CrewFavor.builder()
                .crew(crewRepository.findById(crew.id()).orElseThrow())
                .askedBy(userRepository.findById(asker.id()).orElseThrow())
                .onDate(LocalDate.now().minusDays(3))
                .slot(CrewFavorSlot.MORNING)
                .status(CrewFavorStatus.OPEN)
                .build()).getId();

        java.util.List<Long> ids = idsOf(body(
                mockMvc.perform(get("/api/crews/{c}/favors", crew.id())
                                .header("Authorization", "Bearer " + asker.token()))
                        .andExpect(status().isOk())));

        assertThat(ids).contains(upcoming);
        assertThat(ids)
                .as("""
                        지난 부탁을 남겨 두면 목록의 위쪽이 아무도 못 맡는 카드로 막힌다.                         지우지는 않는다 — 맡은 사람에게는 지난 약속도 기록이다.""")
                .doesNotContain(past);
    }

    // ───────────── 방장 넘기기 · 크루 지우기 ─────────────

    @Test
    @DisplayName("방장을 넘기면 나갈 수 있게 된다 — 막는 쪽만 있고 푸는 쪽이 없으면 갇힌다")
    void transferringOwnershipLetsTheOldOwnerLeave() throws Exception {
        Account owner = accountIn("처음방장", SEONGDONG);
        Account member = account("다음방장");
        Crew crew = crewWith(owner, member);

        // 넘기기 전에는 못 나간다.
        mockMvc.perform(delete("/api/crews/{c}/members/me", crew.id())
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isBadRequest());

        JsonNode after = body(mockMvc.perform(
                        put("/api/crews/{c}/owner/{u}", crew.id(), member.id())
                                .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isOk()));
        assertThat(after.path("owner").asBoolean())
                .as("넘긴 사람은 더 이상 방장이 아니다")
                .isFalse();

        // 이제 나갈 수 있다.
        mockMvc.perform(delete("/api/crews/{c}/members/me", crew.id())
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNoContent());
    }

    @Test
    @DisplayName("방장이 아니면 못 넘기고, 그 방에 없는 사람에게도 못 넘긴다")
    void onlyTheOwnerTransfersAndOnlyToAMember() throws Exception {
        Account owner = accountIn("방장", SEONGDONG);
        Account member = account("멤버");
        Account outsider = account("남");
        Crew crew = crewWith(owner, member);

        mockMvc.perform(put("/api/crews/{c}/owner/{u}", crew.id(), owner.id())
                        .header("Authorization", "Bearer " + member.token()))
                .andExpect(status().isForbidden());

        mockMvc.perform(put("/api/crews/{c}/owner/{u}", crew.id(), outsider.id())
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("혼자 남았을 때만 크루를 지운다 — 남의 대화를 지우는 버튼은 없다")
    void aCrewIsOnlyDeletedWhenTheOwnerIsAlone() throws Exception {
        Account owner = accountIn("방장", SEONGDONG);
        Account member = account("멤버");
        Crew crew = crewWith(owner, member);

        mockMvc.perform(delete("/api/crews/{c}", crew.id())
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isConflict());
        assertThat(crewRepository.findById(crew.id())).isPresent();

        // 멤버가 나가면 혼자다.
        mockMvc.perform(delete("/api/crews/{c}/members/me", crew.id())
                        .header("Authorization", "Bearer " + member.token()))
                .andExpect(status().isNoContent());

        mockMvc.perform(delete("/api/crews/{c}", crew.id())
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNoContent());
        assertThat(crewRepository.findById(crew.id())).isEmpty();
    }

    @Test
    @DisplayName("크루를 지우면 그 크루의 부탁과 달력 줄까지 사라진다")
    void deletingACrewTakesItsFavorsAndCalendarLines() throws Exception {
        Account owner = accountIn("방장", SEONGDONG);
        Account member = account("멤버");
        Crew crew = crewWith(owner, member);

        long favorId = postFavor(owner, crew.id(), null, null).path("id").asLong();
        long scheduleId = body(take(member, crew.id(), favorId).andExpect(status().isOk()))
                .path("scheduleId").asLong();

        mockMvc.perform(delete("/api/crews/{c}/members/me", crew.id())
                        .header("Authorization", "Bearer " + member.token()))
                .andExpect(status().isNoContent());
        mockMvc.perform(delete("/api/crews/{c}", crew.id())
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNoContent());

        assertThat(favorRepository.findById(favorId)).isEmpty();
        assertThat(scheduleRepository.findById(scheduleId))
                .as("""
                        crew_favor 는 CASCADE 로 사라지지만 일정은 다른 표다 — 안 거두면 \
                        없는 크루의 약속이 사람들 달력에 남는다.""")
                .isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private record Crew(long id, long roomId) { }

    private Account account(String nickname) {
        return newAccount(nickname, null);
    }

    private Account accountIn(String nickname, String neighborhoodCode) {
        return newAccount(nickname, neighborhoodCode);
    }

    private Account newAccount(String nickname, String neighborhoodCode) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("favor-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .neighborhoodCode(neighborhoodCode)
                .ageGroup(User.AgeGroup.OVER14)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /** 방장의 가족에 넣는다 — 멤버십의 원본은 방이다(ADR-0011). 크루 방과는 다른 종류다. */
    private void joinFamily(Account owner, Account joiner) throws Exception {
        long roomId = body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"보리네\"}"))
                .andExpect(status().isCreated())).path("roomId").asLong();
        String code = body(mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isCreated())).path("code").asText();
        mockMvc.perform(post("/api/chat/invites/{code}/join", code)
                        .header("Authorization", "Bearer " + joiner.token()))
                .andExpect(status().isOk());
    }

    private long dogOf(Account owner, String name) {
        Dog dog = dogRepository.save(Dog.builder()
                .user(userRepository.findById(owner.id()).orElseThrow())
                .name(name)
                .build());
        return dog.getId();
    }

    /** 첫 계정이 방장인 공개 크루를 만들고 나머지를 넣는다. */
    private Crew crewWith(Account owner, Account... members) throws Exception {
        JsonNode created = body(mockMvc.perform(post("/api/crews")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"품앗이 크루\",\"visibility\":\"public\"}"))
                .andExpect(status().isCreated()));
        long crewId = created.path("id").asLong();

        for (Account member : members) {
            mockMvc.perform(post("/api/crews/{c}/members/me", crewId)
                            .header("Authorization", "Bearer " + member.token()))
                    .andExpect(status().isOk());
        }
        return new Crew(crewId, created.path("roomId").asLong());
    }

    private JsonNode postFavor(Account asker, long crewId, Long dogId, String note)
            throws Exception {
        String json = """
                {"onDate":"%s","slot":"afternoon"%s%s}"""
                .formatted(SOON,
                        dogId == null ? "" : ",\"dogId\":" + dogId,
                        note == null ? "" : ",\"note\":\"" + note + "\"");
        return body(mockMvc.perform(post("/api/crews/{c}/favors", crewId)
                        .header("Authorization", "Bearer " + asker.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isCreated()));
    }

    private ResultActions take(Account taker, long crewId, long favorId) throws Exception {
        return mockMvc.perform(post("/api/crews/{c}/favors/{f}/take", crewId, favorId)
                .header("Authorization", "Bearer " + taker.token()));
    }

    /** 그 사람의 달력 한 달치. 주인을 안 주면 볼 수 있는 전부가 온다. */
    private ResultActions calendar(Account account) throws Exception {
        return mockMvc.perform(get("/api/schedules")
                .param("from", SOON.minusDays(7).toString())
                .param("to", SOON.plusDays(7).toString())
                .header("Authorization", "Bearer " + account.token()));
    }

    private static java.util.List<Long> idsOf(JsonNode array) {
        java.util.List<Long> ids = new java.util.ArrayList<>();
        array.forEach(node -> ids.add(node.path("id").asLong()));
        return ids;
    }

    private static JsonNode lineOf(JsonNode array, long scheduleId) {
        for (JsonNode node : array) {
            if (node.path("id").asLong() == scheduleId) {
                return node;
            }
        }
        throw new AssertionError("달력에 그 줄이 없다: " + scheduleId);
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(StandardCharsets.UTF_8));
    }
}
