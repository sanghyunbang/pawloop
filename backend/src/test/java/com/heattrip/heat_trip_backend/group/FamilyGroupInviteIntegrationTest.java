package com.heattrip.heat_trip_backend.group;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.chat.ChatLimits;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoom;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomInvite;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMember;
import com.heattrip.heat_trip_backend.chat.entity.ChatRoomMemberRole;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomInviteRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomMemberRepository;
import com.heattrip.heat_trip_backend.chat.repository.ChatRoomRepository;
import com.heattrip.heat_trip_backend.group.entity.FamilyGroup;
import com.heattrip.heat_trip_backend.group.repository.FamilyGroupRepository;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 가족을 만들고 · 코드를 보내고 · 코드로 들어오는 세 가지를 <b>HTTP 로</b> 확인한다 —
 * 이슈 #75 완료 조건 1~7.
 *
 * <h2>왜 통합 테스트인가</h2>
 * <p>이 이슈가 보증해야 하는 것들이 전부 <b>여러 계층에 걸쳐 있다.</b>
 * "회수하면 즉시 410" 은 서비스 판정 + 전역 예외 처리기의 봉투 + 계약의 상태 코드가 함께
 * 맞아야 성립하고, "그룹과 방이 같은 트랜잭션" 은 스프링 프록시가 실제로 걸려 있어야 성립한다.
 * 목으로 나누면 각 조각은 초록불인데 합쳐진 동작이 틀릴 수 있다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} <b>두 줄뿐인 것은
 * 의도다</b> — {@code AuthContractIntegrationTest}·{@code AuthMeIntegrationTest} 와 컨텍스트
 * 캐시를 공유한다. {@code @MockBean} 이나 {@code @TestPropertySource} 를 하나라도 붙이면
 * 캐시 키가 갈라져 스프링 컨텍스트가 한 번 더 뜬다(#21). 정원을 낮춰 시험하고 싶어도
 * {@code ChatLimits} 를 목으로 갈아끼우지 않고 <b>진짜 정원까지 채우는</b> 이유가 그것이다.
 *
 * <p><b>{@code @Transactional} 을 붙이지 않은 것도 의도다.</b> 완료 조건 7 은 "그룹만 만들어지고
 * 방이 안 만들어진 상태가 커밋되지 않는가" 인데, 테스트가 트랜잭션을 감싸 버리면 롤백 여부를
 * 정의상 볼 수 없다({@code AuthTokenRefreshIntegrationTest} 가 같은 이유로 붙이지 않았다).
 */
@SpringBootTest
@AutoConfigureMockMvc
class FamilyGroupInviteIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Autowired
    private FamilyGroupRepository familyGroupRepository;

    @Autowired
    private ChatRoomRepository chatRoomRepository;

    @Autowired
    private ChatRoomMemberRepository chatRoomMemberRepository;

    @Autowired
    private ChatRoomInviteRepository chatRoomInviteRepository;

    @Autowired
    private ChatLimits chatLimits;

    // ─────────────────── 완료 조건 1 — 두 계정이 한 가족으로 ───────────────────

    @Test
    @DisplayName("두 계정이 초대코드로 한 가족에 묶이고, 양쪽의 GET /api/groups/me 가 같은 멤버 목록을 준다")
    void twoAccountsJoinOneFamily_andBothSeeTheSameMemberList() throws Exception {
        Account owner = account("보리아빠");
        Account joiner = account("보리엄마");

        JsonNode created = createGroup(owner, "보리네 가족");
        String code = issueInvite(owner, created.path("roomId").asLong());

        JsonNode joined = body(join(joiner, code).andExpect(status().isOk()));
        assertThat(joined.path("id").asLong())
                .as("입장 응답의 방이 그룹의 방이어야 앱이 그 방으로 이동할 수 있다")
                .isEqualTo(created.path("roomId").asLong());

        JsonNode fromOwner = myGroup(owner);
        JsonNode fromJoiner = myGroup(joiner);

        assertThat(fromJoiner.path("id").asLong())
                .as("초대코드로 들어온 사람에게도 같은 그룹이 보여야 한다 — 멤버십 표가 하나이기 때문이다")
                .isEqualTo(fromOwner.path("id").asLong());
        assertThat(memberSummary(fromOwner))
                .as("""
                        양쪽이 같은 목록을 봐야 한다. 멤버십을 group_member 와 chat_room_member 둘로 \
                        나눴다면 여기서 두 목록이 갈린다 (ADR-0011 결정 1).""")
                .isEqualTo(memberSummary(fromJoiner))
                .containsExactly(owner.id() + ":OWNER", joiner.id() + ":MEMBER");
        assertThat(fromOwner.path("members").get(0).path("nickname").asText())
                .as("chat 은 사용자를 id 로만 안다 — 이름을 붙이는 것은 group 의 일이다")
                .isEqualTo("보리아빠");
    }

    @Test
    @DisplayName("속한 가족이 없으면 GET /api/groups/me 는 404 다")
    void withoutAFamily_myGroupIs404() throws Exception {
        Account nobody = account("혼자");

        mockMvc.perform(get("/api/groups/me").header("Authorization", "Bearer " + nobody.token()))
                .andExpect(status().isNotFound());
    }

    // ─────────────────── 완료 조건 2·6 — 회수 ───────────────────

    @Test
    @DisplayName("회수한 코드는 즉시 410 INVITE_REVOKED 이고, 이미 들어와 있던 멤버는 그대로 남는다")
    void revokingACode_blocksItImmediatelyButKeepsTheMembersWhoAlreadyJoined() throws Exception {
        Account owner = account("방장");
        Account early = account("먼저 들어온 사람");
        Account late = account("나중에 온 사람");

        long roomId = createGroup(owner, "회수 테스트").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        join(early, code).andExpect(status().isOk());

        revoke(owner, roomId, code).andExpect(status().isNoContent());

        join(late, code)
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("INVITE_REVOKED"))
                .andExpect(jsonPath("$.error.message").isNotEmpty())
                .andExpect(jsonPath("$.error.traceId").isNotEmpty());

        assertThat(memberSummary(myGroup(early)))
                .as("""
                        회수는 '이 코드로는 이제 못 들어온다' 이지 '들어온 사람을 내보낸다' 가 아니다. \
                        유출 대응이 기존 멤버를 함께 쫓아내는 것이면 방장은 회수를 못 누른다.""")
                .containsExactly(owner.id() + ":OWNER", early.id() + ":MEMBER");
    }

    @Test
    @DisplayName("회수된 코드(410)와 없던 코드(404)가 구별된다 — 회수를 DELETE 로 바꾸면 이 구별이 사라진다")
    void aRevokedCodeAndAnUnknownCodeAreDifferentAnswers() throws Exception {
        Account owner = account("방장");
        Account stranger = account("모르는 사람");

        long roomId = createGroup(owner, "삭제 금지").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        revoke(owner, roomId, code).andExpect(status().isNoContent());

        join(stranger, code)
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("INVITE_REVOKED"));
        join(stranger, "ZZZZZ-ZZZZZ")
                .andExpect(status().isNotFound());

        assertThat(chatRoomInviteRepository.findByCode(code))
                .as("""
                        완료 조건 6: 회수를 DELETE FROM chat_room_invite 로 되돌리면 이 케이스가 깨진다. \
                        행이 사라지면 위의 410 이 404 가 되어 두 답이 한 덩어리가 되고, 유출된 코드를 \
                        회수한 방장이 '이 링크는 이제 안 됩니다' 를 확인할 방법도 함께 사라진다.""")
                .isPresent();
    }

    @Test
    @DisplayName("이미 회수된 코드를 다시 회수해도 204 다 — 최초 회수 시각을 덮어쓰지 않는다")
    void revokingTwiceIsStillSuccess() throws Exception {
        Account owner = account("방장");

        long roomId = createGroup(owner, "두 번 회수").path("roomId").asLong();
        String code = issueInvite(owner, roomId);

        revoke(owner, roomId, code).andExpect(status().isNoContent());
        LocalDateTime first = chatRoomInviteRepository.findByCode(code).orElseThrow().getRevokedAt();
        revoke(owner, roomId, code).andExpect(status().isNoContent());

        assertThat(chatRoomInviteRepository.findByCode(code).orElseThrow().getRevokedAt())
                .as("최초 회수 시각이 사건 기록이다")
                .isEqualTo(first);
    }

    // ─────────────────── 완료 조건 3 — 만료 · 정원 · 봉투 ───────────────────

    @Test
    @DisplayName("만료가 지난 코드는 410 INVITE_EXPIRED 이고 봉투가 {error:{code,message,traceId}} 다")
    void anExpiredCodeIsGone_withTheSharedErrorEnvelope() throws Exception {
        Account owner = account("방장");
        Account late = account("늦은 사람");

        long roomId = createGroup(owner, "만료 테스트").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        expire(code);

        MockHttpServletResponse response = join(late, code)
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("INVITE_EXPIRED"))
                .andExpect(jsonPath("$.error.message").isNotEmpty())
                .andExpect(jsonPath("$.error.traceId").isNotEmpty())
                .andReturn().getResponse();

        String payload = response.getContentAsString(StandardCharsets.UTF_8);
        assertThat(fieldNames(MAPPER.readTree(payload)))
                .as("봉투를 새로 만들지 않는다 — 최상위 필드는 error 하나다 (#10)")
                .containsExactly("error");
        assertThat(payload)
                .as("문구에 식별자를 섞으면 그 순간 유출 경로다 (#6)")
                .doesNotContain(code);
    }

    @Test
    @DisplayName("정원이 찬 방은 409 ROOM_MEMBER_LIMIT 이다 — 한도는 ChatLimits 가 답한다")
    void aFullRoomRefusesWithTheMemberLimitCode() throws Exception {
        Account owner = account("방장");
        Account late = account("자리 없는 사람");

        long roomId = createGroup(owner, "정원 테스트").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        fillRoomToCapacity(roomId, owner.id());

        join(late, code)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("ROOM_MEMBER_LIMIT"))
                .andExpect(jsonPath("$.error.message").isNotEmpty())
                .andExpect(jsonPath("$.error.traceId").isNotEmpty());

        assertThat(chatRoomInviteRepository.findByCode(code).orElseThrow().getUsedCount())
                .as("""
                        못 들어온 요청이 사용 횟수를 쓰면, 상한이 있는 코드가 아무도 못 들어온 채 \
                        소진된다. 증가와 멤버 생성이 하나의 트랜잭션이라 함께 되돌아간다.""")
                .isZero();
    }

    @Test
    @DisplayName("검사 순서가 계약이다 — 만료·폐기·소진 중 둘 이상이면 앞의 것이 답이다")
    void theCheckOrderIsTheContract() throws Exception {
        Account owner = account("방장");
        Account late = account("늦은 사람");

        long roomId = createGroup(owner, "순서 테스트").path("roomId").asLong();

        // 만료됐고 회수도 된 코드 → 만료가 먼저다.
        String both = issueInvite(owner, roomId);
        expire(both);
        revoke(owner, roomId, both).andExpect(status().isNoContent());
        join(late, both)
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("INVITE_EXPIRED"));

        // 회수됐고 소진도 된 코드 → 회수가 먼저다.
        String revokedAndUsedUp = issueInvite(owner, roomId);
        exhaust(revokedAndUsedUp);
        revoke(owner, roomId, revokedAndUsedUp).andExpect(status().isNoContent());
        join(late, revokedAndUsedUp)
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("INVITE_REVOKED"));

        // 소진만 된 코드 → 소진이다. (#9 의 RefreshTokenService 가 순서를 주석으로 못 박은 것과 같다.)
        String usedUp = issueInvite(owner, roomId);
        exhaust(usedUp);
        join(late, usedUp)
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("INVITE_USES_EXHAUSTED"))
                .andExpect(jsonPath("$.error.message").isNotEmpty())
                .andExpect(jsonPath("$.error.traceId").isNotEmpty());
    }

    // ─────────────────── 완료 조건 4 — OWNER 만 ───────────────────

    @Test
    @DisplayName("방장이 아닌 멤버는 발급도 회수도 못 한다 — 403")
    void aPlainMemberCanNeitherIssueNorRevoke() throws Exception {
        Account owner = account("방장");
        Account member = account("그냥 멤버");

        long roomId = createGroup(owner, "인가 테스트").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        join(member, code).andExpect(status().isOk());

        mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                        .header("Authorization", "Bearer " + member.token()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("FORBIDDEN"));

        revoke(member, roomId, code).andExpect(status().isForbidden());

        assertThat(chatRoomInviteRepository.findByCode(code).orElseThrow().getRevokedAt())
                .as("403 을 받았는데 회수가 일어났다면 인가가 응답에만 붙어 있는 것이다")
                .isNull();
    }

    @Test
    @DisplayName("남의 방 id 로 부르면 403 이다 — 404 면 방 id 를 훑어 있는 방을 가려낼 수 있다")
    void someoneElsesRoomIdIsForbidden_notNotFound() throws Exception {
        Account owner = account("방장");
        Account stranger = account("남");

        long someoneElsesRoom = createGroup(owner, "남의 가족").path("roomId").asLong();

        mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", someoneElsesRoom)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isForbidden());

        // 없는 방과 남의 방이 같은 답이어야 존재 여부가 새지 않는다.
        mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", someoneElsesRoom + 100_000)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isForbidden());
    }

    // ─────────────────── 완료 조건 5 — 멱등 ───────────────────

    @Test
    @DisplayName("같은 사람이 같은 코드로 두 번 들어와도 멤버 행이 1개이고 used_count 가 1이다")
    void joiningTwiceChangesNothingTheSecondTime() throws Exception {
        Account owner = account("방장");
        Account joiner = account("두 번 누른 사람");

        long roomId = createGroup(owner, "멱등 테스트").path("roomId").asLong();
        String code = issueInvite(owner, roomId);

        join(joiner, code).andExpect(status().isOk());
        // 사용자가 답답해서 다시 누른 것을 실패로 돌려주면 앱이 보여줄 화면이 없다.
        join(joiner, code).andExpect(status().isOk());

        assertThat(chatRoomMemberRepository.findByRoomIdAndRemovedAtIsNull(roomId))
                .as("UNIQUE (room_id, user_id) 가 두 번째 행을 애초에 막는다")
                .hasSize(2);
        assertThat(chatRoomInviteRepository.findByCode(code).orElseThrow().getUsedCount())
                .as("이미 멤버인 사람은 자리를 새로 쓰지 않는다 — 그래서 소진 검사보다 앞에서 단락한다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("나갔던 사람이 다시 들어오면 기존 행이 되살아난다 — 새 행이 생기지 않는다")
    void aMemberWhoLeftIsRevivedRatherThanReinserted() throws Exception {
        Account owner = account("방장");
        Account leaver = account("나갔다 온 사람");

        long roomId = createGroup(owner, "재입장 테스트").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        join(leaver, code).andExpect(status().isOk());

        // 나가기·강퇴 경로는 M2.6·M2.7 이라 지금은 행을 직접 눕힌다.
        ChatRoomMember row = chatRoomMemberRepository
                .findByRoomIdAndUserId(roomId, leaver.id()).orElseThrow();
        row.setRemovedAt(LocalDateTime.now());
        row.setLastReadSeq(7L);
        chatRoomMemberRepository.saveAndFlush(row);

        join(leaver, code).andExpect(status().isOk());

        ChatRoomMember revived = chatRoomMemberRepository
                .findByRoomIdAndUserId(roomId, leaver.id()).orElseThrow();
        assertThat(revived.getId())
                .as("지우고 다시 넣으면 last_read_seq 가 사라져 미읽음이 처음부터 다시 쌓인다")
                .isEqualTo(row.getId());
        assertThat(revived.getRemovedAt()).isNull();
        assertThat(revived.getLastReadSeq()).isEqualTo(7L);
    }

    @Test
    @DisplayName("재입장 금지 대상은 유효한 코드로도 못 들어온다 — 403")
    void aBlockedMemberCannotComeBackWithAValidCode() throws Exception {
        Account owner = account("방장");
        Account blocked = account("강퇴당한 사람");

        long roomId = createGroup(owner, "재입장 금지 테스트").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        join(blocked, code).andExpect(status().isOk());

        // 강퇴는 M2.7 이다. 지금 정하는 것은 "그 표식이 찍혀 있으면 어떻게 되는가" 하나다.
        ChatRoomMember row = chatRoomMemberRepository
                .findByRoomIdAndUserId(roomId, blocked.id()).orElseThrow();
        row.setRemovedAt(LocalDateTime.now());
        row.setRemovedBy(owner.id());
        row.setRejoinBlocked(true);
        chatRoomMemberRepository.saveAndFlush(row);

        join(blocked, code).andExpect(status().isForbidden());

        assertThat(chatRoomInviteRepository.findByCode(code).orElseThrow().getUsedCount())
                .as("막힌 요청이 사용 횟수를 쓰면 강퇴당한 사람이 남의 코드를 소진시킬 수 있다")
                .isEqualTo(1);
    }

    // ─────────────────── 동시 요청 (📌 #86 원칙 5) ───────────────────

    @Test
    @DisplayName("같은 사람이 같은 코드로 동시에 두 번 들어와도 둘 다 200 이다 — 예전에는 한쪽이 500 이었다")
    void joiningTwiceAtTheSameMomentIsStillIdempotent() throws Exception {
        Account owner = account("방장");
        Account joiner = account("두 번 동시에 누른 사람");

        long roomId = createGroup(owner, "동시 멱등").path("roomId").asLong();
        String code = issueInvite(owner, roomId);

        List<Integer> statuses = joinAtTheSameMoment(List.of(joiner, joiner), List.of(code, code));

        assertThat(statuses)
                .as("""
                        계약은 이 경우를 멱등 200 이라고 선언한다. 예전에는 뒤에 온 요청이 '멤버 아님' \
                        스냅샷을 들고 INSERT 로 내려가 Duplicate entry '<room>-<user>' for key \
                        'chat_room_member.uq_chat_member' 를 냈고, 그게 500 INTERNAL 로 나갔다 — \
                        실제로는 가입에 성공했는데 앱에는 서버 오류로 보였다. \
                        ChatRoomService.joinByInviteCode 에서 lockForMemberChange 를 지우거나 \
                        READ_COMMITTED 를 지우면 여기가 [200, 500] 로 빨간불이다.""")
                .containsExactly(200, 200);
        assertThat(chatRoomMemberRepository.findByRoomIdAndRemovedAtIsNull(roomId)).hasSize(2);
        assertThat(chatRoomInviteRepository.findByCode(code).orElseThrow().getUsedCount())
                .as("멱등 경로는 사용 횟수를 쓰지 않는다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("네 사람이 서로 다른 코드로 같은 방에 동시에 들어와도 전원 200 이다 — 예전에는 InnoDB 데드락이었다")
    void fourPeopleWithFourCodesCanEnterTheSameRoomAtOnce() throws Exception {
        Account owner = account("방장");
        long roomId = createGroup(owner, "동시 참여").path("roomId").asLong();

        List<Account> joiners = new ArrayList<>();
        List<String> codes = new ArrayList<>();
        for (int i = 0; i < 4; i++) {
            joiners.add(account("동시에 온 사람 " + i));
            codes.add(issueInvite(owner, roomId));
        }

        List<Integer> statuses = joinAtTheSameMoment(joiners, codes);

        assertThat(statuses)
                .as("""
                        '가족 단톡방에 링크를 뿌리면 여러 명이 동시에 누른다' 가 이 기능의 가장 흔한 \
                        사용 패턴이다. 예전에는 insertMemberIfRoomHasSpace 가 정원을 세는 서브쿼리로 \
                        chat_room_member 를 room_id 범위로 훑으면서 같은 범위에 INSERT 해서 \
                        'Deadlock found when trying to get lock' 이 났고, 넷 중 셋이 500 이었다. \
                        방을 잠그고 시작하는 것이 그 경합을 없앤다 — lockForMemberChange 를 지우면 \
                        여기가 빨간불이다.""")
                .containsExactly(200, 200, 200, 200);
        assertThat(chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(roomId))
                .as("방장 + 넷")
                .isEqualTo(5);
    }

    @Test
    @DisplayName("마지막 한 번 남은 코드를 두 사람이 동시에 쓰면 진 쪽은 409 INVITE_USES_EXHAUSTED 다")
    void whenTheLastUseIsRacedFor_theLoserIsToldItIsExhausted() throws Exception {
        Account owner = account("방장");
        Account first = account("먼저 쓴 사람");
        Account second = account("한 발 늦은 사람");

        long roomId = createGroup(owner, "소진 경합").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        limitToOneUse(code);

        List<String> errorCodes = new ArrayList<>();
        List<Integer> statuses =
                joinAtTheSameMoment(List.of(first, second), List.of(code, code), errorCodes);

        assertThat(statuses).containsExactlyInAnyOrder(200, 409);
        assertThat(errorCodes)
                .as("""
                        예전에는 진 쪽이 INVITE_REVOKED(410) 를 받았다 — 아무도 회수하지 않은 코드에 \
                        대해서다. recheckDeadState 가 Optional.map(...).orElse(INVITE_REVOKED) 였고, \
                        Optional.map 은 매퍼가 null 을 돌려주면 empty 를 만들기 때문에 '살아 있다(null)' \
                        가 전부 orElse 로 흘렀다. 앱은 error.code 로 화면을 가르므로 \
                        '방장이 링크를 내렸습니다' 라는 거짓 안내가 나갔다. \
                        recheckDeadState 를 그 형태로 되돌리면 여기가 빨간불이다.""")
                .contains("INVITE_USES_EXHAUSTED")
                .doesNotContain("INVITE_REVOKED");
        assertThat(chatRoomInviteRepository.findByCode(code).orElseThrow().getUsedCount())
                .as("상한이 1이면 정확히 한 번만 쓰인다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("나갔던 사람이 동시에 두 번 재입장해도 둘 다 200 이다 — 정원 50 인 방에 409 를 내지 않는다")
    void rejoiningTwiceAtTheSameMomentIsNotAMemberLimit() throws Exception {
        Account owner = account("방장");
        Account leaver = account("나갔다 동시에 두 번 온 사람");

        long roomId = createGroup(owner, "재입장 경합").path("roomId").asLong();
        String code = issueInvite(owner, roomId);
        join(leaver, code).andExpect(status().isOk());

        ChatRoomMember row = chatRoomMemberRepository
                .findByRoomIdAndUserId(roomId, leaver.id()).orElseThrow();
        row.setRemovedAt(LocalDateTime.now());
        chatRoomMemberRepository.saveAndFlush(row);

        List<String> errorCodes = new ArrayList<>();
        List<Integer> statuses =
                joinAtTheSameMoment(List.of(leaver, leaver), List.of(code, code), errorCodes);

        assertThat(statuses)
                .as("""
                        예전에는 진 쪽이 409 ROOM_MEMBER_LIMIT 을 받았다 — 정원은 50 이고 방에는 \
                        2명뿐인데도. reviveIfRemoved 의 'where removed_at is not null' 은 이미 \
                        되살아난 뒤에 0 을 돌려주는데, 호출부가 그 0 을 무조건 정원 초과로 옮겼기 \
                        때문이다. 영향 행 수 0 에 뜻이 둘이면 그건 판정이 아니다.""")
                .containsExactly(200, 200);
        assertThat(errorCodes).doesNotContain("ROOM_MEMBER_LIMIT");
        assertThat(chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(roomId)).isEqualTo(2);
    }

    // ─────────────────── 재발급은 이전 코드를 죽이지 않는다 ───────────────────

    @Test
    @DisplayName("코드를 다시 발급해도 이전 코드는 살아 있다 — 유출 대응은 회수(DELETE)뿐이다")
    void issuingASecondCodeDoesNotRevokeTheFirstOne() throws Exception {
        Account owner = account("방장");
        Account joiner = account("옛 코드를 들고 온 사람");

        long roomId = createGroup(owner, "재발급 테스트").path("roomId").asLong();
        String first = issueInvite(owner, roomId);
        String second = issueInvite(owner, roomId);

        assertThat(second).isNotEqualTo(first);
        assertThat(chatRoomInviteRepository.findByCode(first).orElseThrow().getRevokedAt())
                .as("""
                        2026-08 이전에는 schema.md §14 · openapi.yaml · ChatErrorCode 셋이 \
                        '재발급하면 이전 코드는 즉시 폐기된다' 고 적었고 구현은 그렇게 하지 않았다. \
                        문서를 믿고 '새 코드 발급' 을 유출 대응 버튼으로 만들면 그 버튼은 \
                        아무것도 막지 않는다. 이 테스트는 셋 중 어느 쪽으로 가든 코드와 문서가 \
                        같은 말을 하게 잡아 둔다 — 구현을 바꾸기로 하면 여기를 함께 바꿔야 한다.""")
                .isNull();
        join(joiner, first).andExpect(status().isOk());

        // 유출 대응 수단은 그 코드를 지목해 회수하는 것뿐이다.
        Account late = account("회수 뒤에 온 사람");
        revoke(owner, roomId, first).andExpect(status().isNoContent());
        join(late, first)
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.error.code").value("INVITE_REVOKED"));
        join(late, second)
                .andExpect(status().isOk());
    }

    // ─────────────────── 생성은 한 번뿐 ───────────────────

    @Test
    @DisplayName("이미 가족이 있는 계정의 두 번째 생성은 409 다 — 보이지 않는 그룹을 만들지 않는다")
    void creatingASecondFamilyIsRejected() throws Exception {
        Account owner = account("두 번 만든 사람");

        JsonNode first = createGroup(owner, "첫 가족");
        long groupsBefore = familyGroupRepository.count();

        mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"둘째 가족\"}"))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.error.code").value("CONFLICT"));

        assertThat(myGroup(owner).path("id").asLong())
                .as("""
                        예전에는 둘 다 201 이었고, GET /api/groups/me 는 참여 순서로 첫 그룹만 \
                        돌려주므로 두 번째 그룹은 구현된 어떤 읽기 경로로도 볼 수 없었다 — \
                        사용자가 존재도 삭제도 모르는 행이다. 생성 응답이 타임아웃돼 앱이 재시도하면 \
                        조용히 그 상태가 된다.""")
                .isEqualTo(first.path("id").asLong());
        assertThat(familyGroupRepository.count())
                .as("거절된 요청은 그룹 행을 남기지 않는다")
                .isEqualTo(groupsBefore);
    }

    @Test
    @DisplayName("가족을 나갔던(removed_at) 계정은 다시 만들 수 있다 — 조회가 404 인데 생성도 막으면 갇힌다")
    void anAccountWithNoLiveFamilyCanCreateAgain() throws Exception {
        Account owner = account("나갔던 사람");

        long roomId = createGroup(owner, "옛 가족").path("roomId").asLong();
        ChatRoomMember row = chatRoomMemberRepository
                .findByRoomIdAndUserId(roomId, owner.id()).orElseThrow();
        row.setRemovedAt(LocalDateTime.now());
        chatRoomMemberRepository.saveAndFlush(row);

        mockMvc.perform(get("/api/groups/me").header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNotFound());

        // 시끄러운 게이트는 지워진다 — 409 는 "지금 조회가 답하는 가족이 있을 때" 만이다.
        createGroup(owner, "새 가족");
    }

    // ─────────────────── 완료 조건 7 — 원자성 ───────────────────

    @Test
    @DisplayName("그룹을 만들면 같은 트랜잭션에서 방과 OWNER 멤버십이 함께 생긴다")
    void creatingAGroupAlsoCreatesTheRoomAndTheOwnerMembership() throws Exception {
        Account owner = account("방장");

        JsonNode created = createGroup(owner, "우리 가족");

        ChatRoom room = chatRoomRepository
                .findByOriginKindAndOriginRef("FAMILY", String.valueOf(created.path("id").asLong()))
                .orElseThrow(() -> new AssertionError(
                        "방이 없다. 그룹 생성에서 방 생성을 떼어내면 여기서 걸린다 (완료 조건 7)"));

        assertThat(room.getId()).isEqualTo(created.path("roomId").asLong());
        assertThat(room.getTag()).isEqualTo("가족");
        assertThat(chatRoomMemberRepository.findByRoomIdAndUserId(room.getId(), owner.id()))
                .as("방장이 없는 방은 초대코드를 발급할 사람이 없어 영원히 아무도 못 들어온다")
                .get()
                .extracting(ChatRoomMember::getRole)
                .isEqualTo(ChatRoomMemberRole.OWNER);
    }

    @Test
    @DisplayName("방 생성이 실패하면 그룹 행도 커밋되지 않는다 — 방 없는 그룹이 남지 않는다")
    void whenTheRoomCannotBeCreated_theGroupRowIsRolledBackToo() throws Exception {
        Account owner = account("방장");

        // 다음 family_group.id 를 알아내 그 자리의 방을 미리 차지한다.
        // InnoDB 의 AUTO_INCREMENT 는 지운 값을 다시 쓰지 않으므로 다음 id 는 probe + 1 이다.
        FamilyGroup probe = familyGroupRepository.saveAndFlush(
                FamilyGroup.builder().name("자리 확인용").build());
        long nextGroupId = probe.getId() + 1;
        familyGroupRepository.delete(probe);
        familyGroupRepository.flush();

        chatRoomRepository.saveAndFlush(ChatRoom.builder()
                .originKind("FAMILY").originRef(String.valueOf(nextGroupId))
                .name("먼저 자리를 차지한 방").tag("가족").build());

        mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"방을 못 만드는 가족\"}"))
                .andExpect(status().is5xxServerError());

        assertThat(familyGroupRepository.findById(nextGroupId))
                .as("""
                        UNIQUE (origin_kind, origin_ref) 가 방 INSERT 를 거부한 상황이다.
                        FamilyGroupService.create 에서 @Transactional 을 떼면 여기가 빨간불이다 \
                        (실제로 떼어 확인했다) — SimpleJpaRepository.save 가 자기 트랜잭션으로 \
                        그룹 행을 커밋해 버리고 '방 없는 가족' 이 남는다. 그 그룹은 초대코드를 \
                        발급할 방장이 없어 아무도 못 들어오는데 화면에서는 정상으로 보인다 (완료 조건 7).
                        반대로 openRoom 을 REQUIRES_NEW 로 바꾸는 것은 여기에 안 잡힌다 — 예외가 \
                        create 밖으로 나가 바깥 트랜잭션도 함께 롤백되기 때문이고, 그 차이는 \
                        ChatRoomService javadoc 에 적었다.""")
                .isEmpty();
    }

    // ─────────────────── 인가 경계 (📌 #86 원칙 4) ───────────────────

    @Test
    @DisplayName("토큰 없이 부르면 다섯 경로가 전부 401 이고 본문이 없다")
    void withoutAToken_everyNewEndpointIs401() throws Exception {
        assertUnauthorized(post("/api/groups")
                .contentType(MediaType.APPLICATION_JSON).content("{\"name\":\"x\"}"));
        assertUnauthorized(get("/api/groups/me"));
        assertUnauthorized(post("/api/chat/rooms/{roomId}/invites", 1));
        assertUnauthorized(delete("/api/chat/rooms/{roomId}/invites/{code}", 1, "AAAAA-AAAAA"));
        assertUnauthorized(post("/api/chat/invites/{code}/join", "AAAAA-AAAAA"));
    }

    @Test
    @DisplayName("이름이 비었으면 400 이고, 그 요청은 그룹도 방도 만들지 않는다")
    void anInvalidNameIsRejectedBeforeAnythingIsCreated() throws Exception {
        Account owner = account("방장");
        long before = familyGroupRepository.count();

        mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"   \"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("VALIDATION"));

        assertThat(familyGroupRepository.count()).isEqualTo(before);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    @Test
    @DisplayName("가족과 멤버의 시각이 오프셋을 달고 나간다 — 실제 HTTP 응답에서 잰다 (#248)")
    void groupTimestampsCarryAnOffset() throws Exception {
        Account owner = account("시각 보는 아빠");
        Account joiner = account("시각 보는 엄마");

        JsonNode created = createGroup(owner, "시각 보는 가족");
        String code = issueInvite(owner, created.path("roomId").asLong());
        join(joiner, code).andExpect(status().isOk());

        JsonNode group = myGroup(owner);
        carriesOffset(group, "createdAt");
        assertThat(group.path("members")).hasSizeGreaterThan(1);
        for (JsonNode member : group.path("members")) {
            carriesOffset(member, "joinedAt");
        }

        // 생성 응답도 같은 모양이어야 한다 — 여기만 빠지면 가족을 막 만든 사람의 화면이 어긋난다.
        carriesOffset(created, "createdAt");
    }

    /**
     * 이 필드가 <b>오프셋을 단 RFC3339 문자열</b>인가 — 이슈 #248.
     *
     * <p>{@code Group.createdAt} 과 {@code GroupMember.joinedAt} 이 2026-09-03 이전에는
     * 오프셋 없이 나갔다. 앱의 {@code DateTime.parse} 는 그런 문자열을 <b>기기 지역 시각</b>
     * 으로 읽으므로, 해외에 있는 가족이 보면 그 차이만큼 어긋난다.
     */
    private static void carriesOffset(JsonNode node, String field) {
        JsonNode value = node.path(field);
        assertThat(value.isTextual())
                .as("%s 가 문자열이 아니다(%s) — 숫자면 매퍼가 타임스탬프로 낸 것이다", field, value)
                .isTrue();
        assertThat(value.asText())
                .as("%s 에 오프셋이 없다 — 계약의 format: date-time 은 RFC3339 오프셋을 요구한다", field)
                .matches("\\d{4}-\\d{2}-\\d{2}T[\\d:.]+(Z|[+-]\\d{2}:\\d{2})");
    }


    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("family-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private JsonNode createGroup(Account owner, String name) throws Exception {
        return body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\"}".formatted(name)))
                .andExpect(status().isCreated()));
    }

    private String issueInvite(Account owner, long roomId) throws Exception {
        return body(mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isCreated()))
                .path("code").asText();
    }

    private ResultActions revoke(Account account, long roomId, String code) throws Exception {
        return mockMvc.perform(delete("/api/chat/rooms/{roomId}/invites/{code}", roomId, code)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions join(Account account, String code) throws Exception {
        return mockMvc.perform(post("/api/chat/invites/{code}/join", code)
                .header("Authorization", "Bearer " + account.token()));
    }

    /**
     * 여러 요청을 <b>실제로 같은 순간에</b> 출발시킨다 — {@link CyclicBarrier} 가 출발선이다.
     *
     * <p>이 지그가 없어서 동시성 결함 넷이 466건의 초록불을 그대로 통과했다. 스레드를 띄우는
     * 테스트가 저장소에 하나도 없었고, 순차 재요청만 보는 테스트는 이 경로를 정의상 지나지
     * 않는다({@code joiningTwiceChangesNothingTheSecondTime} 이 그랬다).
     *
     * <p>{@code MockMvc} 는 서블릿 컨테이너 없이 디스패처를 직접 부르므로 스레드마다 요청이
     * 독립이고, 서비스·트랜잭션·실제 MySQL 은 그대로 지나간다 — 여기서 재는 것이 정확히 그
     * 셋의 경합이다.
     */
    private List<Integer> joinAtTheSameMoment(List<Account> accounts, List<String> codes)
            throws Exception {
        return joinAtTheSameMoment(accounts, codes, new ArrayList<>());
    }

    private List<Integer> joinAtTheSameMoment(List<Account> accounts, List<String> codes,
                                              List<String> errorCodesOut) throws Exception {
        int size = accounts.size();
        CyclicBarrier startLine = new CyclicBarrier(size);
        int[] statuses = new int[size];
        String[] errorCodes = new String[size];
        List<Thread> threads = new ArrayList<>();

        for (int i = 0; i < size; i++) {
            final int index = i;
            Thread thread = new Thread(() -> {
                try {
                    startLine.await();
                    MockHttpServletResponse response =
                            join(accounts.get(index), codes.get(index)).andReturn().getResponse();
                    statuses[index] = response.getStatus();
                    errorCodes[index] =
                            errorCodeOf(response.getContentAsString(StandardCharsets.UTF_8));
                } catch (Exception thrown) {
                    // 여기로 오면 요청이 응답조차 못 만든 것이다. 상태 코드 자리에 그것을 남긴다.
                    statuses[index] = -1;
                    errorCodes[index] = thrown.getClass().getSimpleName();
                }
            });
            threads.add(thread);
            thread.start();
        }
        for (Thread thread : threads) {
            thread.join();
        }

        List<Integer> result = new ArrayList<>();
        for (int i = 0; i < size; i++) {
            result.add(statuses[i]);
            errorCodesOut.add(errorCodes[i]);
        }
        return result;
    }

    /** 오류 본문의 {@code error.code}. 성공 응답이면 {@code "-"} 다. */
    private static String errorCodeOf(String payload) {
        try {
            return MAPPER.readTree(payload).path("error").path("code").asText("-");
        } catch (Exception notAnError) {
            return "-";
        }
    }

    /** 사용 횟수를 한 번만 쓸 수 있게 만든다. 지금 기본값은 무제한이라 경합을 만들 수 없다. */
    private void limitToOneUse(String code) {
        ChatRoomInvite invite = chatRoomInviteRepository.findByCode(code).orElseThrow();
        invite.setMaxUses(1);
        chatRoomInviteRepository.saveAndFlush(invite);
    }

    private JsonNode myGroup(Account account) throws Exception {
        return body(mockMvc.perform(get("/api/groups/me")
                        .header("Authorization", "Bearer " + account.token()))
                .andExpect(status().isOk()));
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(StandardCharsets.UTF_8));
    }

    /** 멤버 목록을 {@code <userId>:<role>} 로 눕힌다 — 두 응답을 그대로 비교하기 위해서다. */
    private static List<String> memberSummary(JsonNode group) {
        List<String> summary = new ArrayList<>();
        for (JsonNode member : group.path("members")) {
            summary.add(member.path("userId").asLong() + ":" + member.path("role").asText());
        }
        return summary;
    }

    /** 코드의 유효기간을 과거로 민다. 벽시계를 기다리지 않고 만료 경계를 보는 방법이다. */
    private void expire(String code) {
        ChatRoomInvite invite = chatRoomInviteRepository.findByCode(code).orElseThrow();
        invite.setExpiresAt(LocalDateTime.now().minusDays(1));
        chatRoomInviteRepository.saveAndFlush(invite);
    }

    /** 사용 횟수를 다 쓴 상태로 만든다. 상한을 0 으로 두면 첫 사용부터 소진이다. */
    private void exhaust(String code) {
        ChatRoomInvite invite = chatRoomInviteRepository.findByCode(code).orElseThrow();
        invite.setMaxUses(0);
        chatRoomInviteRepository.saveAndFlush(invite);
    }

    /**
     * 방을 정원까지 채운다.
     *
     * <p>정원 값을 여기 적지 않고 {@link ChatLimits} 에게 묻는다 — 한도를 바꾸면 이 테스트도
     * 따라간다. 사용자 행을 만들지 않는 이유는 {@code chat_room_member.user_id} 가 값일 뿐
     * {@code users} 로 FK 를 내지 않기 때문이다(ADR-0011 결정 4). 그 성질이 여기서 보인다.
     */
    private void fillRoomToCapacity(long roomId, long ownerUserId) {
        ChatRoom room = chatRoomRepository.findById(roomId).orElseThrow();
        long seats = chatLimits.maxMembersPerRoom(ownerUserId)
                - chatRoomMemberRepository.countByRoomIdAndRemovedAtIsNull(roomId);
        for (long seat = 0; seat < seats; seat++) {
            chatRoomMemberRepository.saveAndFlush(ChatRoomMember.builder()
                    .room(room)
                    .userId(-1L - seat)   // 음수 id — 실제 계정과 겹치지 않는다
                    .build());
        }
    }

    private void assertUnauthorized(MockHttpServletRequestBuilder request) throws Exception {
        MockHttpServletResponse response = mockMvc.perform(request)
                .andExpect(status().isUnauthorized())
                .andReturn().getResponse();

        assertThat(response.getContentAsString(StandardCharsets.UTF_8))
                .as("401 은 본문이 없다 — 원인을 실으면 그게 유출 경로다 (#5·#6)")
                .isEmpty();
    }

    private static List<String> fieldNames(JsonNode node) {
        List<String> names = new ArrayList<>();
        node.fieldNames().forEachRemaining(names::add);
        return names;
    }
}
