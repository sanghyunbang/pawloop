package com.heattrip.heat_trip_backend.crew;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMemberRole;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomMemberRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomRepository;
import com.heattrip.heat_trip_backend.crew.repository.CrewRepository;
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
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 크루를 만들고 · 찾고 · 들어오고 · 나가는 것을 <b>HTTP 로</b> 확인한다 — 이슈 #417.
 *
 * <h2>왜 통합 테스트인가</h2>
 * <p>이 이슈가 보증해야 하는 것이 전부 <b>모듈 둘에 걸쳐</b> 있다. "크루를 만들면 방이 함께
 * 생긴다" 는 {@code crew} 와 {@code chat} 이 같은 트랜잭션에 있어야 성립하고, "크루를 나가면
 * 방에서도 나간다" 는 애초에 <b>나갈 곳이 하나뿐</b>이라는 사실을 재는 것이라 DB 를 봐야 한다.
 * 목으로 나누면 각 조각은 초록불인데 합쳐진 동작이 틀릴 수 있다.
 *
 * <p>애너테이션이 두 줄뿐인 것은 의도다 — 컨텍스트 캐시를 다른 통합 테스트와 공유한다.
 * {@code @MockBean} 을 하나라도 붙이면 캐시 키가 갈라져 스프링이 한 번 더 뜬다(#21).
 * 정원을 시험할 때 {@code ChatLimits} 를 갈아끼우지 않고 <b>크루 정원을 2로 만드는</b>
 * 이유가 그것이다.
 *
 * <p>{@code @Transactional} 도 안 붙인다. "방 생성이 실패하면 크루 행도 함께 롤백되는가" 를
 * 테스트가 트랜잭션으로 감싸면 정의상 볼 수 없다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CrewIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    /** 성동구 왕십리2동. 앞 다섯 자리 11200 이 성동구다. */
    private static final String SEONGDONG = "1120052000";

    /** 같은 성동구의 다른 동(성수1가1동) — 옆 동네가 같은 목록에 잡혀야 한다. */
    private static final String SEONGDONG_NEXT_DONG = "1120064000";

    /** 종로구 — 다른 구. 이건 안 잡혀야 한다. */
    private static final String JONGNO = "1111051500";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Autowired
    private CrewRepository crewRepository;

    @Autowired
    private ChatRoomRepository chatRoomRepository;

    @Autowired
    private ChatRoomMemberRepository chatRoomMemberRepository;

    // ───────────── 완료 조건 1 — 만들면 방이 함께 생기고 방장이 멤버다 ─────────────

    @Test
    @DisplayName("크루를 만들면 chat_room 이 함께 생기고 만든 사람이 그 방의 OWNER 다")
    void creatingACrewOpensARoomAndMakesTheCreatorItsOwner() throws Exception {
        Account owner = accountIn("성수아빠", SEONGDONG);

        JsonNode created = create(owner, "{\"name\":\"성수동 아침 산책\"}");

        long crewId = created.path("id").asLong();
        long roomId = created.path("roomId").asLong();
        assertThat(roomId).as("방 id 를 안 주면 화면이 방으로 가려고 한 번 더 물어야 한다").isPositive();

        ChatRoom room = chatRoomRepository.findById(roomId).orElseThrow();
        assertThat(room.getOriginKind())
                .as("출처 종류가 CREW 여야 chat 이 가족방 코드와 크루 코드를 가른다")
                .isEqualTo("CREW");
        assertThat(room.getOriginRef())
                .as("origin_ref 가 크루 id 다 — 이 이음매가 끊기면 방에서 크루를 못 되찾는다")
                .isEqualTo(String.valueOf(crewId));
        assertThat(room.getTag())
                .as("채팅 목록이 이 값을 사람이 읽는 라벨로 그린다 — 가족방은 '가족' 이다")
                .isEqualTo("크루");
        assertThat(room.getName())
                .as("방 이름이 크루 이름을 베낀다 — 채팅 목록에서 같은 모임으로 보여야 한다")
                .isEqualTo("성수동 아침 산책");

        ChatRoomMember membership = chatRoomMemberRepository
                .findByRoomIdAndUserId(roomId, owner.id()).orElseThrow();
        assertThat(membership.getRole())
                .as("방장이 없는 방은 초대코드도 못 내고 강퇴도 못 한다")
                .isEqualTo(ChatRoomMemberRole.OWNER);
        assertThat(created.path("owner").asBoolean()).isTrue();
        assertThat(created.path("mine").asBoolean()).isTrue();
        assertThat(created.path("memberCount").asInt()).isEqualTo(1);

        assertThat(created.path("visibility").asText())
                .as("처음부터 아무나 들어오면 관리가 안 된다 — 기본은 초대다")
                .isEqualTo("invite");
        assertThat(created.path("capacity").asInt()).isEqualTo(20);
        assertThat(created.path("neighborhoodCode").asText())
                .as("동네를 안 주면 내 동네다 — 모임을 만드는 사람은 대개 자기 동네에 만든다")
                .isEqualTo(SEONGDONG);
    }

    @Test
    @DisplayName("크루 행이 있는데 방이 없는 상태가 안 생긴다 — 이름이 방 길이를 넘으면 둘 다 롤백")
    void whenTheRoomCannotBeCreated_theCrewRowIsRolledBackToo() throws Exception {
        Account owner = accountIn("긴이름", SEONGDONG);
        long before = crewRepository.count();

        // crew.name 은 30자까지고 chat_room.name 은 50자까지다. 31자는 서비스가 앞에서
        // 막는다 — 그 거절이 크루 행을 남기지 않는 것을 잰다.
        mockMvc.perform(post("/api/crews")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + "가".repeat(31) + "\"}"))
                .andExpect(status().isBadRequest());

        assertThat(crewRepository.count())
                .as("거절된 요청이 행을 남기면 아무도 못 보는 크루가 쌓인다")
                .isEqualTo(before);
    }

    // ───────────── 완료 조건 2 — 초대 코드 · 정원 ─────────────

    @Test
    @DisplayName("초대 코드로 들어오면 방 멤버가 되고, 크루 정원을 넘으면 409 다")
    void joiningByCodeAddsAMemberAndTheCrewCapacityRejectsTheThird() throws Exception {
        Account owner = accountIn("정원방장", SEONGDONG);
        Account second = account("두번째");
        Account third = account("세번째");

        JsonNode crew = create(owner, "{\"name\":\"둘만 걷는 모임\",\"capacity\":2}");
        long crewId = crew.path("id").asLong();
        long roomId = crew.path("roomId").asLong();
        String code = issueInvite(owner, roomId);

        JsonNode joined = body(joinByCode(second, code).andExpect(status().isOk()));
        assertThat(joined.path("id").asLong()).isEqualTo(crewId);
        assertThat(joined.path("mine").asBoolean()).isTrue();
        assertThat(joined.path("owner").asBoolean())
                .as("들어온 사람은 방장이 아니다")
                .isFalse();
        assertThat(chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(roomId)).isEqualTo(2);

        joinByCode(third, code)
                .andExpect(status().isConflict());

        assertThat(chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(roomId))
                .as("""
                        정원을 넘긴 요청이 예외를 던지면 트랜잭션이 통째로 되돌아간다 — \
                        멤버 행도, 초대코드 사용 횟수도 안 쓴다.""")
                .isEqualTo(2);
    }

    @Test
    @DisplayName("가족방 코드로는 크루 참여 경로를 못 지나간다 — 403")
    void aFamilyInviteCodeCannotBeUsedOnTheCrewJoinPath() throws Exception {
        Account owner = account("가족방장");
        Account outsider = account("남");

        JsonNode group = body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"보리네 가족\"}"))
                .andExpect(status().isCreated()));
        String familyCode = issueInvite(owner, group.path("roomId").asLong());

        joinByCode(outsider, familyCode)
                .andExpect(status().isForbidden());
    }

    // ───────────── 완료 조건 3 — 우리 동네로 찾는다 ─────────────

    @Test
    @DisplayName("우리 동네 목록이 같은 구의 공개 크루만 준다 — 다른 구도, 초대 크루도 빠진다")
    void theNeighbourhoodListKeepsOnlyPublicCrewsOfTheSameDistrict() throws Exception {
        Account seongdong = accountIn("성동사람", SEONGDONG);
        Account nextDong = accountIn("성수사람", SEONGDONG_NEXT_DONG);
        Account jongno = accountIn("종로사람", JONGNO);

        long mine = create(seongdong, "{\"name\":\"성동 공개\",\"visibility\":\"public\"}")
                .path("id").asLong();
        long neighbours = create(nextDong, "{\"name\":\"성수 공개\",\"visibility\":\"public\"}")
                .path("id").asLong();
        long invite = create(seongdong, "{\"name\":\"성동 초대\"}").path("id").asLong();
        long far = create(jongno, "{\"name\":\"종로 공개\",\"visibility\":\"public\"}")
                .path("id").asLong();

        List<Long> ids = idsOf(body(list(seongdong, "?scope=neighborhood")
                .andExpect(status().isOk())));

        assertThat(ids)
                .as("같은 구의 옆 동네 모임이 안 보이면 동네 모임이 성립하지 않는다 — 앞 다섯 자리로 찾는다")
                .contains(mine, neighbours);
        assertThat(ids)
                .as("초대 크루가 목록에 뜨면 '초대' 라는 말이 뜻을 잃는다")
                .doesNotContain(invite);
        assertThat(ids)
                .as("다른 구의 모임이 섞이면 '우리 동네' 가 뜻을 잃는다")
                .doesNotContain(far);
    }

    @Test
    @DisplayName("동네를 안 고른 사람은 우리 동네 목록에서 400 — 좌표로 대신 찾지 않는다")
    void withoutANeighbourhoodTheListAsksYouToPickOne() throws Exception {
        Account nowhere = account("동네없는사람");

        list(nowhere, "?scope=neighborhood").andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("동네를 안 고르면 공개 크루를 못 만든다 — 아무도 못 찾는 공개가 되기 때문이다")
    void aPublicCrewWithoutANeighbourhoodIsRejected() throws Exception {
        Account nowhere = account("동네없는방장");

        mockMvc.perform(post("/api/crews")
                        .header("Authorization", "Bearer " + nowhere.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"어디에도 없는 모임\",\"visibility\":\"public\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("내 크루 목록은 내가 든 것만 준다 — 남의 공개 크루는 안 섞인다")
    void theMineListOnlyHasCrewsIAmIn() throws Exception {
        Account me = accountIn("나", SEONGDONG);
        Account other = accountIn("남", SEONGDONG);

        long mine = create(me, "{\"name\":\"내 모임\"}").path("id").asLong();
        long theirs = create(other, "{\"name\":\"남의 공개 모임\",\"visibility\":\"public\"}")
                .path("id").asLong();

        List<Long> ids = idsOf(body(list(me, "").andExpect(status().isOk())));

        assertThat(ids)
                .as("scope 를 안 주면 내 크루다 — 크루 화면을 여는 사람 대부분은 든 모임을 보러 온다")
                .containsExactly(mine)
                .doesNotContain(theirs);
    }

    // ───────────── 완료 조건 4 — 방장이 아니면 403 ─────────────

    @Test
    @DisplayName("방장이 아니면 고치기도 강퇴도 403 이다")
    void aNonOwnerCanNeitherEditNorKick() throws Exception {
        Account owner = accountIn("진짜방장", SEONGDONG);
        Account member = account("그냥멤버");

        JsonNode crew = create(owner, "{\"name\":\"성수 저녁 산책\",\"visibility\":\"public\"}");
        long crewId = crew.path("id").asLong();
        join(member, crewId).andExpect(status().isOk());

        mockMvc.perform(patch("/api/crews/{id}", crewId)
                        .header("Authorization", "Bearer " + member.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"내가 바꾼 이름\"}"))
                .andExpect(status().isForbidden());

        mockMvc.perform(delete("/api/crews/{id}/members/{userId}", crewId, owner.id())
                        .header("Authorization", "Bearer " + member.token()))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("방장이 이름을 고치면 방 이름도 함께 바뀐다 — 한쪽만 바뀌면 같은 모임이 둘로 보인다")
    void renamingTheCrewRenamesItsRoom() throws Exception {
        Account owner = accountIn("이름고치는방장", SEONGDONG);

        JsonNode crew = create(owner, "{\"name\":\"옛 이름\"}");
        long crewId = crew.path("id").asLong();
        long roomId = crew.path("roomId").asLong();

        JsonNode edited = body(mockMvc.perform(patch("/api/crews/{id}", crewId)
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"새 이름\",\"intro\":\"천천히 걷습니다\",\"capacity\":8}"))
                .andExpect(status().isOk()));

        assertThat(edited.path("name").asText()).isEqualTo("새 이름");
        assertThat(edited.path("intro").asText()).isEqualTo("천천히 걷습니다");
        assertThat(edited.path("capacity").asInt()).isEqualTo(8);
        assertThat(chatRoomRepository.findById(roomId).orElseThrow().getName())
                .as("방 이름이 안 따라오면 채팅 목록에 옛 이름이 남는다")
                .isEqualTo("새 이름");
    }

    @Test
    @DisplayName("정원만 보낸 PATCH 가 이름을 안 건드린다 — 부분 수정이 계약대로 가능하다")
    void aPatchWithOnlyOneFieldLeavesTheRestAlone() throws Exception {
        Account owner = accountIn("부분수정방장", SEONGDONG);

        JsonNode crew = create(owner,
                "{\"name\":\"그대로 둘 이름\",\"intro\":\"그대로 둘 소개\"}");
        long crewId = crew.path("id").asLong();

        JsonNode edited = body(mockMvc.perform(patch("/api/crews/{id}", crewId)
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"capacity\":5}"))
                .andExpect(status().isOk()));

        assertThat(edited.path("capacity").asInt()).isEqualTo(5);
        assertThat(edited.path("name").asText())
                .as("""
                        만들기 스키마를 PATCH 에 재사용하면 정원만 줄이려는 사람이 이름을 \
                        함께 보내야 하고, 그 이름이 그 사이 바뀐 값이면 되돌려 버린다 \
                        (ADR-0017 규약 4).""")
                .isEqualTo("그대로 둘 이름");
        assertThat(edited.path("intro").asText()).isEqualTo("그대로 둘 소개");
        assertThat(edited.path("neighborhoodCode").asText()).isEqualTo(SEONGDONG);
    }

    @Test
    @DisplayName("빈 본문 PATCH 는 400 이다 — 아무것도 안 바뀐 200 을 성공으로 읽게 두지 않는다")
    void anEmptyPatchIsRejected() throws Exception {
        Account owner = accountIn("빈본문방장", SEONGDONG);
        long crewId = create(owner, "{\"name\":\"빈 본문 모임\"}").path("id").asLong();

        mockMvc.perform(patch("/api/crews/{id}", crewId)
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("공개로 바꾸면서 동네를 떼면 400 — 만들 때만 막고 고칠 때 열어 두면 문이 남는다")
    void turningPublicWhileClearingTheNeighbourhoodIsRejected() throws Exception {
        Account owner = accountIn("동네떼는방장", SEONGDONG);
        long crewId = create(owner, "{\"name\":\"동네 있는 모임\"}").path("id").asLong();

        mockMvc.perform(patch("/api/crews/{id}", crewId)
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"visibility\":\"public\",\"neighborhoodCode\":\"\"}"))
                .andExpect(status().isBadRequest());
    }

    // ───────────── 완료 조건 6 — 나가면 방에서도 나간다 ─────────────

    @Test
    @DisplayName("크루를 나가면 방 멤버십도 닫힌다 — 나갈 곳이 하나뿐이다")
    void leavingTheCrewClosesTheRoomMembership() throws Exception {
        Account owner = accountIn("방장", SEONGDONG);
        Account member = account("나가는사람");

        JsonNode crew = create(owner, "{\"name\":\"들락날락\",\"visibility\":\"public\"}");
        long crewId = crew.path("id").asLong();
        long roomId = crew.path("roomId").asLong();
        join(member, crewId).andExpect(status().isOk());

        mockMvc.perform(delete("/api/crews/{id}/members/me", crewId)
                        .header("Authorization", "Bearer " + member.token()))
                .andExpect(status().isNoContent());

        ChatRoomMember row = chatRoomMemberRepository
                .findByRoomIdAndUserId(roomId, member.id()).orElseThrow();
        assertThat(row.getRemovedAt())
                .as("한쪽만 남는 상태가 없다 — 크루 멤버십이라는 것이 따로 없기 때문이다")
                .isNotNull();
        assertThat(row.isRejoinBlocked())
                .as("제 발로 나간 사람에게 재입장 금지를 걸면, 그 사람은 왜 못 들어오는지 알 길이 없다")
                .isFalse();

        assertThat(idsOf(body(list(member, "").andExpect(status().isOk()))))
                .doesNotContain(crewId);

        // 나갔다가 다시 들어올 수 있다 — 금지를 안 걸었다는 것의 뜻이 이것이다.
        join(member, crewId).andExpect(status().isOk());
        assertThat(chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(roomId)).isEqualTo(2);
    }

    @Test
    @DisplayName("방장은 크루를 못 나간다 — 나가면 초대도 강퇴도 못 하는 방이 남는다")
    void theOwnerCannotLeave() throws Exception {
        Account owner = accountIn("혼자방장", SEONGDONG);
        long crewId = create(owner, "{\"name\":\"혼자 모임\"}").path("id").asLong();

        mockMvc.perform(delete("/api/crews/{id}/members/me", crewId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("강퇴당한 사람은 공개 크루라도 다시 못 들어온다")
    void aKickedMemberCannotComeBackEvenToAPublicCrew() throws Exception {
        Account owner = accountIn("내보내는방장", SEONGDONG);
        Account trouble = account("내보내진사람");

        JsonNode crew = create(owner, "{\"name\":\"공개 모임\",\"visibility\":\"public\"}");
        long crewId = crew.path("id").asLong();
        join(trouble, crewId).andExpect(status().isOk());

        mockMvc.perform(delete("/api/crews/{id}/members/{userId}", crewId, trouble.id())
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNoContent());

        join(trouble, crewId)
                .andExpect(status().isForbidden());
    }

    // ───────────── 보이기 · 안 보이기 ─────────────

    @Test
    @DisplayName("초대 크루는 안 든 사람에게 404 다 — 403 이면 어느 번호에 크루가 있는지 세어진다")
    void anInviteOnlyCrewIsInvisibleToOutsiders() throws Exception {
        Account owner = accountIn("숨은방장", SEONGDONG);
        Account outsider = account("모르는사람");

        long crewId = create(owner, "{\"name\":\"숨은 모임\"}").path("id").asLong();

        detail(outsider, crewId).andExpect(status().isNotFound());
        join(outsider, crewId).andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("공개 크루는 남에게도 보이되 멤버 목록은 안 준다 — 인원 수까지가 공개다")
    void aPublicCrewShowsItsSizeButNotItsPeople() throws Exception {
        Account owner = accountIn("공개방장", SEONGDONG);
        Account outsider = account("구경꾼");

        long crewId = create(owner, "{\"name\":\"열린 모임\",\"visibility\":\"public\"}")
                .path("id").asLong();

        JsonNode seen = body(detail(outsider, crewId).andExpect(status().isOk()));
        assertThat(seen.path("memberCount").asInt()).isEqualTo(1);
        assertThat(seen.path("mine").asBoolean()).isFalse();
        assertThat(seen.path("members"))
                .as("누가 있는지는 안에서만이다")
                .isEmpty();

        JsonNode fromInside = body(detail(owner, crewId).andExpect(status().isOk()));
        assertThat(fromInside.path("members")).hasSize(1);
        assertThat(fromInside.path("members").get(0).path("nickname").asText())
                .isEqualTo("공개방장");
        assertThat(fromInside.path("members").get(0).path("role").asText()).isEqualTo("OWNER");
    }

    // ───────────── 만 14세 미만 ─────────────

    @Test
    @DisplayName("만 14세 미만은 크루를 만들지도 들어가지도 못한다 — 가족방에만 있을 수 있다")
    void minorsCannotCreateOrJoinCrews() throws Exception {
        Account owner = accountIn("어른방장", SEONGDONG);
        Account minor = minorAccount("열세살");

        long crewId = create(owner, "{\"name\":\"어른 모임\",\"visibility\":\"public\"}")
                .path("id").asLong();
        String code = issueInvite(owner, crewIdToRoomId(crewId));

        mockMvc.perform(post("/api/crews")
                        .header("Authorization", "Bearer " + minor.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"어린이 모임\"}"))
                .andExpect(status().isForbidden());

        join(minor, crewId).andExpect(status().isForbidden());
        joinByCode(minor, code).andExpect(status().isForbidden());
    }

    // ───────────── 계약의 시각 (#248) ─────────────

    @Test
    @DisplayName("크루의 createdAt 이 오프셋을 달고 나가고, 값이 정말 지금이다")
    void crewTimestampsCarryAnOffsetAndAreActuallyNow() throws Exception {
        Account owner = accountIn("시각보는방장", SEONGDONG);

        JsonNode created = create(owner, "{\"name\":\"시각 보는 모임\"}");

        String at = created.path("createdAt").asText();
        assertThat(at)
                .as("계약의 format: date-time 은 RFC3339 오프셋을 요구한다")
                .matches("\\d{4}-\\d{2}-\\d{2}T[\\d:.]+(Z|[+-]\\d{2}:\\d{2})");

        Duration off = Duration.between(Instant.parse(at), Instant.now()).abs();
        assertThat(off)
                .as("""
                        오프셋이 붙었는지만 재면 9시간 오차를 못 잡는다 — 형식은 맞고 값이 \
                        틀린 적이 실제로 있었다(#248). 값도 함께 잰다. 지금과 %s 떨어져 있다""", off)
                .isLessThan(Duration.ofMinutes(5));
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        return newAccount(nickname, null, User.AgeGroup.OVER14);
    }

    private Account accountIn(String nickname, String neighborhoodCode) {
        return newAccount(nickname, neighborhoodCode, User.AgeGroup.OVER14);
    }

    private Account minorAccount(String nickname) {
        return newAccount(nickname, null, User.AgeGroup.UNDER14);
    }

    private Account newAccount(String nickname, String neighborhoodCode, User.AgeGroup ageGroup) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("crew-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .neighborhoodCode(neighborhoodCode)
                .ageGroup(ageGroup)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private JsonNode create(Account owner, String json) throws Exception {
        return body(mockMvc.perform(post("/api/crews")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isCreated()));
    }

    private ResultActions list(Account account, String query) throws Exception {
        return mockMvc.perform(get("/api/crews" + query)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions detail(Account account, long crewId) throws Exception {
        return mockMvc.perform(get("/api/crews/{id}", crewId)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions join(Account account, long crewId) throws Exception {
        return mockMvc.perform(post("/api/crews/{id}/members/me", crewId)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions joinByCode(Account account, String code) throws Exception {
        return mockMvc.perform(post("/api/crews/join/{code}", code)
                .header("Authorization", "Bearer " + account.token()));
    }

    private String issueInvite(Account owner, long roomId) throws Exception {
        return body(mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isCreated()))
                .path("code").asText();
    }

    private long crewIdToRoomId(long crewId) {
        return chatRoomRepository.findByOriginKindAndOriginRef("CREW", String.valueOf(crewId))
                .orElseThrow().getId();
    }

    private static List<Long> idsOf(JsonNode array) {
        List<Long> ids = new ArrayList<>();
        array.forEach(node -> ids.add(node.path("id").asLong()));
        return ids;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(StandardCharsets.UTF_8));
    }
}
