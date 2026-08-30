package com.heattrip.heat_trip_backend.care;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.care.entity.CareLog;
import com.heattrip.heat_trip_backend.care.entity.CareType;
import com.heattrip.heat_trip_backend.care.repository.CareLogRepository;
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
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 오늘의 케어 공유와 산책 주의사항을 <b>HTTP 로</b> 확인한다 — 이슈 #76 완료 조건 1~6.
 *
 * <h2>인가가 이 이슈의 핵심이라 통합 테스트여야 한다</h2>
 * <p>"남의 가족 기록이 한 건도 안 나온다" 는 <b>인가 판정 + 조회 필터 + 전역 예외 처리기의
 * 상태 코드</b> 셋이 함께 맞아야 성립한다. 서비스만 목으로 부르면 셋 중 하나가 빠져도
 * 초록불이 난다. 특히 {@code ResponseStatusException(403)} 은 전역 처리기에 분기가 없으면
 * <b>500</b> 으로 나가고, 그건 서비스 단위 테스트에서 정의상 안 보인다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} <b>두 줄뿐인 것은
 * 의도다</b> — {@code FamilyGroupInviteIntegrationTest}·{@code AuthMeIntegrationTest} 와
 * 글자 그대로 같아야 스프링 컨텍스트 캐시를 공유한다(#21). {@code @MockBean}·
 * {@code @TestPropertySource} 를 하나라도 붙이면 캐시 키가 갈라져 컨텍스트가 한 번 더 뜬다.
 *
 * <p>{@code @Transactional} 을 붙이지 않은 것도 같은 파일들과 맞춘 것이다 — 이 테스트는
 * "다른 계정이 <b>다음 요청에서</b> 그 사실을 본다" 를 보는데, 테스트가 트랜잭션을 감싸면
 * 커밋되지 않은 것을 같은 트랜잭션 안에서 보는 것이 되어 검증이 공허해진다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class CareSharingIntegrationTest extends AbstractMySqlIntegrationTest {

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
    private CareLogRepository careLogRepository;

    // ─────────────────── 완료 조건 1 — 한 가족의 두 계정이 서로의 기록을 본다 ───────────────────

    @Test
    @DisplayName("한쪽이 밥을 찍으면 상대의 다음 조회에 그 사실이 누가·언제와 함께 보인다")
    void whenOneMemberFeeds_theOtherSeesItOnTheNextRead() throws Exception {
        Account dad = account("보리아빠");
        Account mom = account("보리엄마");
        Family family = family(dad, "보리네 가족", mom);

        JsonNode created = body(postCare(dad, family.groupId(), "meal", "사료 반 컵")
                .andExpect(status().isCreated()));

        assertThat(created.path("doneBy").path("userId").asLong())
                .as("수행자는 토큰의 사용자다 — 본문으로 받으면 남의 이름으로 기록을 남길 수 있다")
                .isEqualTo(dad.id());
        assertThat(created.path("dogId").isNull())
                .as("dog 표가 아직 없다 — 검증할 수 없는 외래 id 를 저장하지 않는다(CareLog javadoc)")
                .isTrue();

        JsonNode seenByMom = careLogs(mom, family.groupId(), null);

        assertThat(seenByMom.size()).isEqualTo(1);
        assertThat(seenByMom.get(0).path("type").asText()).isEqualTo("meal");
        assertThat(seenByMom.get(0).path("doneBy").path("nickname").asText())
                .as("""
                        '누가' 를 이름으로 볼 수 없으면 이 화면은 이중 급여를 못 막는다 — \
                        '누군가 밥을 줬다' 는 '내가 줬나?' 를 지우지 못한다.""")
                .isEqualTo("보리아빠");
        assertThat(seenByMom.get(0).path("occurredAt").asText())
                .as("'언제' 가 없으면 아침 밥과 저녁 밥을 구별할 수 없다")
                .isNotBlank();
        assertThat(seenByMom.get(0).path("memo").asText()).isEqualTo("사료 반 컵");
    }

    // ─────────────────── 완료 조건 2 — 막지 말고 알린다 ───────────────────

    @Test
    @DisplayName("같은 날 밥을 두 번 찍으면 둘 다 남는다 — 서버는 두 번째를 거절하지 않는다")
    void feedingTwiceInOneDay_keepsBothRows() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Family family = family(dad, "두 번 먹는 집", mom);

        postCare(dad, family.groupId(), "meal", null).andExpect(status().isCreated());
        postCare(mom, family.groupId(), "meal", null)
                .andExpect(status().isCreated());

        JsonNode logs = careLogs(dad, family.groupId(), "meal");

        assertThat(logs.size())
                .as("""
                        두 번째 기록이 실수인지 사실인지 서버는 모른다 — 아침·저녁 두 번 주는 집에서 \
                        두 번째 밥은 정상이다. 막으면 실제로 한 일이 기록에서 사라지고, 그러면 이 표가 \
                        답해야 하는 질문에 거짓으로 답하게 된다.
                        경고는 앱이 만든다(CareService.record javadoc · today_care_card 위젯 테스트).""")
                .isEqualTo(2);
        assertThat(doers(logs)).containsExactly("아빠", "엄마");
    }

    // ─────────────────── 완료 조건 3·6 — 인가 ───────────────────

    @Test
    @DisplayName("남의 가족 groupId 로 부르면 403 이고, 남의 기록이 응답에 한 건도 없다")
    void anOutsider_isForbiddenAndSeesNoRowOfSomeoneElsesFamily() throws Exception {
        Account dad = account("남의 집 아빠");
        Account outsider = account("남");
        Family family = family(dad, "남의 집", null);

        postCare(dad, family.groupId(), "meal", "비밀 사료").andExpect(status().isCreated());

        for (ResultActions attempt : List.of(
                mockMvc.perform(get("/api/groups/{id}/care-logs", family.groupId())
                        .header("Authorization", "Bearer " + outsider.token())),
                postCare(outsider, family.groupId(), "walk", null),
                mockMvc.perform(get("/api/groups/{id}/walk-notes", family.groupId())
                        .header("Authorization", "Bearer " + outsider.token())),
                replaceWalkNote(outsider, family.groupId(), "내 마음대로"))) {

            String body = attempt.andExpect(status().isForbidden())
                    .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

            assertThat(body)
                    .as("""
                            완료 조건 3 은 '403 이고, 남의 기록이 한 건도 응답에 없다' 둘 다다. \
                            상태 코드만 보면 본문에 행이 실려 나가는 회귀를 놓친다.""")
                    .doesNotContain("비밀 사료")
                    .doesNotContain("남의 집 아빠");
            assertThat(MAPPER.readTree(body).path("error").path("code").asText())
                    .as("봉투는 GlobalExceptionHandler 의 것 하나다 — 사본을 만들지 않는다")
                    .isEqualTo("FORBIDDEN");
        }

        assertThat(careLogRepository.findDayOfGroup(family.groupId(),
                LocalDate.now().atStartOfDay(), LocalDate.now().plusDays(1).atStartOfDay()))
                .as("거절된 POST 가 행을 만들지 않았는지 — 403 인데 저장은 됐다면 그게 더 나쁘다")
                .hasSize(1);
    }

    @Test
    @DisplayName("아예 없는 그룹 id 도 404 가 아니라 403 이다 — 있는 가족/없는 가족을 훑어낼 수 없다")
    void anUnknownGroupId_answersForbiddenNotNotFound() throws Exception {
        Account nobody = account("아무도 아닌 사람");
        long neverExisted = 9_000_000_000L;

        mockMvc.perform(get("/api/groups/{id}/care-logs", neverExisted)
                        .header("Authorization", "Bearer " + nobody.token()))
                .andExpect(status().isForbidden());
    }

    @Test
    @DisplayName("토큰이 없으면 네 경로 모두 401 이고 본문이 없다")
    void withoutAToken_allFourPathsAreUnauthorized() throws Exception {
        Account dad = account("아빠");
        Family family = family(dad, "토큰 없는 요청", null);
        long id = family.groupId();

        for (ResultActions attempt : List.of(
                mockMvc.perform(get("/api/groups/{id}/care-logs", id)),
                mockMvc.perform(post("/api/groups/{id}/care-logs", id)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"type\":\"meal\"}")),
                mockMvc.perform(get("/api/groups/{id}/walk-notes", id)),
                mockMvc.perform(put("/api/groups/{id}/walk-notes", id)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"body\":\"x\"}")))) {

            assertThat(attempt.andExpect(status().isUnauthorized())
                    .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8))
                    .as("401 은 본문이 없다 — 원인을 실으면 그게 유출 경로다 (#5·#6)")
                    .isEmpty();
        }
    }

    // ─────────────────── 완료 조건 5 — 필터는 인가와 다른 방어다 ───────────────────

    @Test
    @DisplayName("두 가족에 모두 속한 사람도 물어본 그룹의 기록만 본다 — group_id 필터를 지우면 여기가 죽는다")
    void aMemberOfTwoGroups_seesOnlyTheGroupTheyAskedFor() throws Exception {
        Account both = account("두 집 살림");
        Account otherOwner = account("옆집 주인");

        Family mine = family(both, "우리 집", null);
        Family theirs = family(otherOwner, "옆집", both);

        postCare(both, mine.groupId(), "meal", "우리 집 밥").andExpect(status().isCreated());
        postCare(otherOwner, theirs.groupId(), "meal", "옆집 밥").andExpect(status().isCreated());

        JsonNode fromMine = careLogs(both, mine.groupId(), null);

        assertThat(memos(fromMine))
                .as("""
                        인가와 필터는 서로를 대신하지 않는다. 이 사람은 두 방의 살아 있는 멤버라 \
                        인가는 두 그룹 다 통과한다 — 그래서 CareLogRepository.findDayOfGroup 의 \
                        'c.group.id = :groupId' 를 지우면 이 단언만 빨간불이 되고, 위의 403 테스트는 \
                        그대로 초록이다. 한 사람이 여러 방에 속하는 것은 초대코드로 실제로 생기는 \
                        상태이지 가정이 아니다.""")
                .containsExactly("우리 집 밥");

        assertThat(memos(careLogs(both, theirs.groupId(), null)))
                .as("같은 사람이 옆집을 물으면 옆집 것만 나온다 — 필터는 사람이 아니라 그룹으로 자른다")
                .containsExactly("옆집 밥");
    }

    // ─────────────────── 날짜 ───────────────────

    @Test
    @DisplayName("어제 기록은 오늘 조회에 안 나오고, date 로 물으면 나온다")
    void yesterdaysRowIsNotTodays() throws Exception {
        Account dad = account("아빠");
        Family family = family(dad, "어제 오늘", null);

        postCare(dad, family.groupId(), "walk", "오늘 산책").andExpect(status().isCreated());
        backdateEverything(family.groupId(), "어제 산책", dad);

        assertThat(memos(careLogs(dad, family.groupId(), null)))
                .as("기본이 오늘이 아니면 '오늘의 케어' 카드가 며칠 전 기록으로 채워진다")
                .containsExactly("오늘 산책");

        JsonNode yesterday = body(mockMvc.perform(
                get("/api/groups/{id}/care-logs", family.groupId())
                        .param("date", LocalDate.now().minusDays(1).toString())
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isOk()));

        assertThat(memos(yesterday)).containsExactly("어제 산책");
    }

    @Test
    @DisplayName("계약에 없는 케어 종류는 400 이다 — 본문에서도 쿼리에서도")
    void anUnknownCareType_is400() throws Exception {
        Account dad = account("아빠");
        Family family = family(dad, "이상한 종류", null);

        mockMvc.perform(post("/api/groups/{id}/care-logs", family.groupId())
                        .header("Authorization", "Bearer " + dad.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"type\":\"grooming\"}"))
                .andExpect(status().isBadRequest());

        mockMvc.perform(get("/api/groups/{id}/care-logs", family.groupId())
                        .param("type", "MEAL")
                        .header("Authorization", "Bearer " + dad.token()))
                .andExpect(status().isBadRequest());
    }

    // ─────────────────── 완료 조건 4 — 산책 주의사항 ───────────────────

    @Test
    @DisplayName("한쪽이 주의사항을 고치면 다른 쪽에 그대로 보이고, 누가 고쳤는지도 함께 보인다")
    void whenOneMemberRewritesTheWalkNote_theOtherSeesIt() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Family family = family(dad, "슬개골 조심", mom);

        assertThat(body(walkNote(mom, family.groupId())).path("body").asText())
                .as("""
                        아직 아무도 안 쓴 상태는 정상이다 — 404 로 답하면 앱이 '오류' 와 '아직 없음' 을 \
                        상태 코드로 갈라야 하고, 네트워크 실패가 같은 자리에서 만난다.""")
                .isEmpty();

        replaceWalkNote(dad, family.groupId(), "오른쪽 뒷다리 슬개골 — 계단 피하기")
                .andExpect(status().isOk());

        JsonNode seenByMom = body(walkNote(mom, family.groupId()));
        assertThat(seenByMom.path("body").asText()).isEqualTo("오른쪽 뒷다리 슬개골 — 계단 피하기");
        assertThat(seenByMom.path("updatedBy").path("nickname").asText())
                .as("누가 고쳤는지가 없으면 서로 다르게 기억하는 주의사항을 맞출 수 없다")
                .isEqualTo("아빠");

        replaceWalkNote(mom, family.groupId(), "계단 피하기\n대형견 만나면 리드줄 짧게")
                .andExpect(status().isOk());

        JsonNode seenByDad = body(walkNote(dad, family.groupId()));
        assertThat(seenByDad.path("body").asText())
                .as("PUT 은 전체 교체다 — 그룹당 한 장이라 두 번째 PUT 이 첫 번째를 덮는다")
                .isEqualTo("계단 피하기\n대형견 만나면 리드줄 짧게");
        assertThat(seenByDad.path("updatedBy").path("nickname").asText()).isEqualTo("엄마");
    }

    @Test
    @DisplayName("주의사항을 두 번 고쳐도 그룹의 행은 하나다 — UNIQUE(group_id) 가 '한 장' 을 지킨다")
    void rewritingTheWalkNote_neverMakesASecondRow() throws Exception {
        Account dad = account("아빠");
        Family family = family(dad, "한 장", null);

        replaceWalkNote(dad, family.groupId(), "첫 번째").andExpect(status().isOk());
        replaceWalkNote(dad, family.groupId(), "두 번째").andExpect(status().isOk());
        replaceWalkNote(dad, family.groupId(), "").andExpect(status().isOk());

        assertThat(body(walkNote(dad, family.groupId())).path("body").asText())
                .as("다 지운 상태도 정상이다 — 행을 지우면 '한 번도 안 쓴' 과 구별되지 않는다")
                .isEmpty();
    }

    @Test
    @DisplayName("500자를 넘는 주의사항은 400 이다 — 잘라서 저장하지 않는다")
    void anOverlongWalkNote_is400() throws Exception {
        Account dad = account("아빠");
        Family family = family(dad, "너무 긴 메모", null);

        replaceWalkNote(dad, family.groupId(), "가".repeat(501))
                .andExpect(status().isBadRequest());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private record Family(long groupId, long roomId) { }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("care-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /**
     * 가족 하나를 <b>공개 경로로만</b> 만든다 — 그룹 생성 · 초대 발급 · 참여.
     *
     * <p>리포지토리로 행을 직접 꽂지 않는 이유: 그러면 "멤버십이 어떻게 생기는가" 를 이 파일이
     * 다시 정의하게 되고, 실제 경로가 만드는 것과 어긋나도 초록불이 난다. 두 번째 사람을
     * 초대코드로 넣는 것이 앱에서 실제로 일어나는 모양이기도 하다.
     */
    private Family family(Account owner, String name, Account joiner) throws Exception {
        JsonNode created = body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + owner.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\"}".formatted(name)))
                .andExpect(status().isCreated()));
        long roomId = created.path("roomId").asLong();

        if (joiner != null) {
            String code = body(mockMvc.perform(post("/api/chat/rooms/{roomId}/invites", roomId)
                            .header("Authorization", "Bearer " + owner.token()))
                    .andExpect(status().isCreated()))
                    .path("code").asText();
            mockMvc.perform(post("/api/chat/invites/{code}/join", code)
                            .header("Authorization", "Bearer " + joiner.token()))
                    .andExpect(status().isOk());
        }
        return new Family(created.path("id").asLong(), roomId);
    }

    private ResultActions postCare(Account account, long groupId, String type, String memo)
            throws Exception {
        String json = memo == null
                ? "{\"type\":\"%s\"}".formatted(type)
                : "{\"type\":\"%s\",\"memo\":\"%s\"}".formatted(type, memo);
        return mockMvc.perform(post("/api/groups/{id}/care-logs", groupId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private JsonNode careLogs(Account account, long groupId, String type) throws Exception {
        var request = get("/api/groups/{id}/care-logs", groupId)
                .header("Authorization", "Bearer " + account.token());
        if (type != null) {
            request = request.param("type", type);
        }
        return body(mockMvc.perform(request).andExpect(status().isOk()));
    }

    private ResultActions walkNote(Account account, long groupId) throws Exception {
        return mockMvc.perform(get("/api/groups/{id}/walk-notes", groupId)
                        .header("Authorization", "Bearer " + account.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.groupId").value(groupId));
    }

    private ResultActions replaceWalkNote(Account account, long groupId, String noteBody)
            throws Exception {
        return mockMvc.perform(put("/api/groups/{id}/walk-notes", groupId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(MAPPER.writeValueAsString(java.util.Map.of("body", noteBody))));
    }

    /**
     * 어제 날짜의 행을 하나 만든다.
     *
     * <p>API 로는 만들 수 없다 — {@code occurredAt} 을 본문으로 받지 않기 때문이고,
     * <b>그게 의도</b>다({@code CareLogRequest} javadoc). 그래서 여기서만 리포지토리로 꽂는다.
     */
    private void backdateEverything(long groupId, String memo, Account doer) {
        careLogRepository.saveAndFlush(CareLog.builder()
                .group(familyGroupRepository.findById(groupId).orElseThrow())
                .type(CareType.WALK)
                .doneBy(userRepository.findById(doer.id()).orElseThrow())
                .occurredAt(LocalDateTime.now().minusDays(1))
                .memo(memo)
                .build());
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse()
                .getContentAsString(StandardCharsets.UTF_8));
    }

    private static List<String> memos(JsonNode logs) {
        List<String> found = new ArrayList<>();
        for (JsonNode log : logs) {
            found.add(log.path("memo").asText());
        }
        return found;
    }

    private static List<String> doers(JsonNode logs) {
        List<String> found = new ArrayList<>();
        for (JsonNode log : logs) {
            found.add(log.path("doneBy").path("nickname").asText());
        }
        return found;
    }
}
