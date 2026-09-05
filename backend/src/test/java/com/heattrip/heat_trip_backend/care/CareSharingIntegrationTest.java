package com.heattrip.heat_trip_backend.care;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.config.ClockConfig;
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
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.within;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
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

    /**
     * {@code chat_room_member.removed_at} 을 찍는 유일한 수단이다 — 강퇴 엔드포인트는 M2.6 이라
     * 아직 없다. 나머지 픽스처는 전부 공개 경로로 만든다({@link #family}).
     */
    @Autowired
    private JdbcTemplate jdbc;

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
                .as("""
                        FK 는 #154 에서 걸렸지만 쓰기 경로가 아직 dogId 를 안 받는다 — 응답은 \
                        여전히 항상 null 이다. 받는 날의 전제는 #209 Dogs-high-3 (CareLog javadoc).""")
                .isTrue();

        JsonNode seenByMom = careLogs(mom, family.groupId(), null);

        assertThat(seenByMom.size()).isEqualTo(1);
        assertThat(seenByMom.get(0).path("type").asText()).isEqualTo("meal");
        assertThat(seenByMom.get(0).path("doneBy").path("nickname").asText())
                .as("""
                        '누가' 를 이름으로 볼 수 없으면 이 화면은 이중 급여를 못 막는다 — \
                        '누군가 밥을 줬다' 는 '내가 줬나?' 를 지우지 못한다.""")
                .isEqualTo("보리아빠");
        String occurredAt = seenByMom.get(0).path("occurredAt").asText();
        assertThat(occurredAt)
                .as("'언제' 가 없으면 아침 밥과 저녁 밥을 구별할 수 없다")
                .isNotBlank();
        assertThat(occurredAt)
                .as("""
                        **오프셋이 붙어야 한다** (#209). 계약이 format: date-time 이라고                         선언했고 그건 RFC3339 오프셋이 있어야 성립한다 — 앱의                         DateTime.tryParse 는 오프셋 없는 문자열을 기기 지역 시각으로 읽으므로                         해외에 있는 가족이 보면 그 차이만큼 어긋난 시각이 그려진다.                         2026-09-03 이전에는 '2026-09-03T00:30:00' 이 그대로 나갔다.""")
                .endsWith("Z");
        assertThat(java.time.Instant.parse(occurredAt))
                .as("숫자 타임스탬프로 나가도 안 된다 — 앱이 파싱하지 못한다")
                .isCloseTo(java.time.Instant.now(), within(5, java.time.temporal.ChronoUnit.MINUTES));
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
                // **서비스 존으로 센다.** 서버의 "오늘" 은 ClockConfig.SERVICE_ZONE 이고
                // (CareService.today), 컬럼에 담긴 값도 그 존의 벽시계다. 여기서
                // LocalDate.now()(JVM 기본 존)로 창을 만들면 **UTC 로 도는 CI 에서만**
                // 하루가 어긋나 이 행이 창 밖으로 나간다 — 15:00~24:00 UTC 에 돌면 빨간불이고
                // 나머지 시간에는 초록이다. 2026-09-03 22:53 UTC 에 실제로 그렇게 터졌다.
                LocalDate.now(ClockConfig.SERVICE_ZONE).atStartOfDay(),
                LocalDate.now(ClockConfig.SERVICE_ZONE).plusDays(1).atStartOfDay()))
                .as("거절된 POST 가 행을 만들지 않았는지 — 403 인데 저장은 됐다면 그게 더 나쁘다")
                .hasSize(1);
    }

    @Test
    @DisplayName("나간·강퇴된 멤버는 옛 가족의 케어를 못 본다 — removed_at 이 찍히면 네 경로 모두 403")
    void aRemovedMember_seesNothingOfTheirFormerFamily() throws Exception {
        Account dad = account("남는 아빠");
        Account leaver = account("나간 사람");
        Family family = family(dad, "누가 나간 집", leaver);

        postCare(dad, family.groupId(), "meal", "비밀 사료").andExpect(status().isCreated());
        replaceWalkNote(dad, family.groupId(), "계단 피하기").andExpect(status().isOk());

        assertThat(stampRemovedAt(family.roomId(), leaver.id()))
                .as("""
                        행을 지우지 않고 removed_at 만 찍는다 — 강퇴가 실제로 하는 일이 그것이고\
                        (ChatRoomMember javadoc), 이 테스트가 보는 것도 '행이 있는가' 가 아니라 \
                        '그 행이 살아 있는가' 여야 한다.""")
                .isEqualTo(1);

        for (ResultActions attempt : List.of(
                mockMvc.perform(get("/api/groups/{id}/care-logs", family.groupId())
                        .header("Authorization", "Bearer " + leaver.token())),
                postCare(leaver, family.groupId(), "walk", "나간 사람의 산책"),
                mockMvc.perform(get("/api/groups/{id}/walk-notes", family.groupId())
                        .header("Authorization", "Bearer " + leaver.token())),
                replaceWalkNote(leaver, family.groupId(), "내 마음대로"))) {

            assertThat(attempt.andExpect(status().isForbidden())
                    .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8))
                    .as("""
                            완료 조건 6 을 잠그는 다른 테스트(anOutsider_...)는 '한 번도 멤버였던 적 \
                            없는 남' 만 본다. 나간 사람은 chat_room_member 행이 남아 있어 검사의 \
                            종류가 다르다 — 존재 여부가 아니라 removed_at 이다. \
                            ChatRoomService.isLiveMember 의 '.filter(removedAt == null)' 을 지우면 \
                            여기가 빨간불이고, 그 줄 없이 초록인 테스트만 있으면 M2.6 의 강퇴가 \
                            새는 채로 들어온다.""")
                    .doesNotContain("비밀 사료")
                    .doesNotContain("계단 피하기");
        }

        assertThat(body(walkNote(dad, family.groupId())).path("body").asText())
                .as("나간 사람의 PUT 이 남은 가족의 메모를 덮지 않았다 — 403 인데 쓰기는 됐다면 그게 더 나쁘다")
                .isEqualTo("계단 피하기");
        assertThat(memos(careLogs(dad, family.groupId(), null)))
                .as("나간 사람의 POST 도 행을 만들지 않았다")
                .containsExactly("비밀 사료");
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
                        // 서버가 세는 존과 같은 존으로 물어야 한다 — 위 주석 참조.
                        .param("date",
                                LocalDate.now(ClockConfig.SERVICE_ZONE).minusDays(1).toString())
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

    // ─────────────────── 탈퇴 — 남은 가족의 것은 남은 가족의 것이다 ───────────────────

    @Test
    @DisplayName("한 명이 탈퇴해도 가족의 주의사항과 케어 기록은 남는다 — 이름만 '알 수 없음' 으로 떨어진다")
    void whenOneMemberWithdraws_theFamilysNotesAndLogsSurvive() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Family family = family(dad, "한 명이 탈퇴하는 집", mom);

        replaceWalkNote(mom, family.groupId(), "오른쪽 뒷다리 슬개골 — 계단 피하기")
                .andExpect(status().isOk());
        postCare(dad, family.groupId(), "meal", "아빠가 준 밥").andExpect(status().isCreated());
        postCare(mom, family.groupId(), "walk", "엄마가 간 산책").andExpect(status().isCreated());

        mockMvc.perform(delete("/auth/me").header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isNoContent());

        JsonNode note = body(walkNote(dad, family.groupId()));
        assertThat(note.path("body").asText())
                .as("""
                        walk_note 는 개인 기록이 아니라 가족 전원이 보는 안전 메모다(슬개골·계단). \
                        '마지막으로 고친 사람' 은 메타데이터인데, updated_by 에 ON DELETE CASCADE 를 \
                        걸면 그 메타데이터 하나 때문에 그룹 소유 문서가 통째로 지워진다. 그러면 남은 \
                        가족의 화면은 '아직 주의사항이 없어요' 를 그리고, 사라졌다는 신호가 아무 데도 \
                        없다 — 빈 화면이 곧 거짓말이 되는 자리다.""")
                .isEqualTo("오른쪽 뒷다리 슬개골 — 계단 피하기");
        assertThat(note.path("updatedBy").path("nickname").asText())
                .as("""
                        이름은 users 행에서 오므로 탈퇴하면 답할 수 없다. 그때 쓰는 문구는 \
                        User.UNKNOWN_DISPLAY_NAME 하나이고, GroupMemberResponse.nickname 이 같은 \
                        상황에서 이미 그 문구를 쓴다 — 같은 사람이 화면마다 다른 이름으로 보이면 안 된다.""")
                .isEqualTo("알 수 없음");

        JsonNode logs = careLogs(dad, family.groupId(), null);
        assertThat(memos(logs))
                .as("""
                        care_log.done_by 의 CASCADE 도 같은 값이다 — 엄마가 탈퇴하면 '오늘 엄마가 \
                        산책을 다녀왔다' 가 아빠 화면에서도 사라지고, 이 이슈가 막으려던 산책 누락이 \
                        바로 그 자리에서 생긴다. '오늘 누가 무엇을 했나' 의 답이 부분적으로 거짓이 된다.""")
                .containsExactly("아빠가 준 밥", "엄마가 간 산책");
        assertThat(doers(logs)).containsExactly("아빠", "알 수 없음");
        assertThat(logs.get(1).path("doneBy").path("userId").asLong())
                .as("""
                        가리킬 사람이 없으면 id 도 없다. 0 은 어떤 users.id 와도 같지 않아서 앱의 \
                        '내가 했는가' 판정(doneBy.userId == 내 id)이 조용히 참이 되는 일이 없다.""")
                .isZero();
    }

    // ─────────────────── #154 완료 조건 4 — 반려동물이 지워져도 케어 기록은 남는다 ───────────────────

    @Test
    @DisplayName("반려동물을 지워도 케어 기록은 남는다 — dogId 만 null 로 떨어진다 (엔티티가 건 FK 의 SET NULL)")
    void whenTheDogIsDeleted_theCareRecordSurvivesWithoutIt() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Family family = family(dad, "반려동물을 잃은 집", mom);
        long careLogId = body(postCare(dad, family.groupId(), "meal", "초코 아침밥")
                .andExpect(status().isCreated())).path("id").asLong();

        // 쓰기 경로가 아직 dogId 를 안 받으므로(#209 Dogs-high-3) DB 에 직접 잇는다. 이 DB 는
        // 엔티티가 만든 것이라, 여기서 재는 것은 22_care_log_dog_fk.sql 이 아니라 CareLog 의
        // @OnDelete 가 실제로 내는 제약이다 — 마이그레이션 실행 테스트와 짝이다.
        jdbc.update("INSERT INTO dog (user_id, name, size, species, neutered, created_at) "
                + "VALUES (?, '초코', 'small', 'dog', 0, UTC_TIMESTAMP(6))", dad.id());
        long dogId = jdbc.queryForObject(
                "SELECT MAX(id) FROM dog WHERE user_id = ?", Long.class, dad.id());
        assertThatThrownBy(() -> jdbc.update(
                "UPDATE care_log SET dog_id = ? WHERE id = ?", dogId + 1_000_000, careLogId))
                .as("fk_carelog_dog — 없는 반려동물 id 는 못 들어간다. FK 가 안 걸렸으면 여기가 통과한다")
                .isInstanceOf(DataIntegrityViolationException.class);
        jdbc.update("UPDATE care_log SET dog_id = ? WHERE id = ?", dogId, careLogId);

        JsonNode before = careLogs(mom, family.groupId(), null);
        assertThat(before.get(0).path("dogId").asLong())
                .as("응답의 dogId 는 dog.id 다 — 늘 null 만 내려온다면 이 단언이 그것을 잡는다")
                .isEqualTo(dogId);

        jdbc.update("DELETE FROM dog WHERE id = ?", dogId);

        JsonNode after = careLogs(mom, family.groupId(), null);
        assertThat(memos(after))
                .as("""
                        케어는 "누가 언제 무엇을 했는가" 의 기록이다. 반려동물이 지워졌다고 '오늘 \
                        아빠가 밥을 줬다' 가 엄마 화면에서 사라지면 이중 급여가 바로 그 자리에서 \
                        생긴다 — group_id·done_by 와 같은 이유로 SET NULL 이다. CASCADE 면 빈 목록이다.""")
                .containsExactly("초코 아침밥");
        assertThat(after.get(0).path("dogId").isNull())
                .as("가리킬 반려동물이 없으면 id 도 없다")
                .isTrue();
    }

    // ─────────────────── #209 Groups-medium-1 — 잘못 찍은 기록은 본인이 지운다 ───────────────────

    @Test
    @DisplayName("내가 찍은 기록은 지울 수 있고, 지우면 가족의 다음 조회에서 사라진다 — 204, 두 번째는 404")
    void myOwnRecord_canBeDeleted_andDisappearsForTheFamily() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Family family = family(dad, "실수로 두 번 찍은 집", mom);
        postCare(dad, family.groupId(), "meal", "아침").andExpect(status().isCreated());
        long mistaken = body(postCare(dad, family.groupId(), "meal", "실수")
                .andExpect(status().isCreated())).path("id").asLong();

        deleteCare(dad, family.groupId(), mistaken).andExpect(status().isNoContent());

        assertThat(memos(careLogs(mom, family.groupId(), null)))
                .as("""
                        서버는 두 번째 밥을 거절하지 않는다(완료 조건 2). 그래서 되돌릴 문이 있어야 \
                        한다 — 없으면 엄마 화면의 '오늘 아빠가 밥을 두 번 줬다' 가 영원히 남고, \
                        사용자는 그 카드를 안 믿는다(#209 Groups-medium-1).""")
                .containsExactly("아침");
        deleteCare(dad, family.groupId(), mistaken)
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("남의 기록은 403 이고 그대로 남는다 — 지울 수 있으면 산책 누락이 그 자리에서 생긴다")
    void someoneElsesRecord_isForbidden_andStays() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Family family = family(dad, "남의 기록을 지우려는 집", mom);
        long momsWalk = body(postCare(mom, family.groupId(), "walk", "엄마가 간 산책")
                .andExpect(status().isCreated())).path("id").asLong();

        deleteCare(dad, family.groupId(), momsWalk).andExpect(status().isForbidden());

        assertThat(memos(careLogs(dad, family.groupId(), null)))
                .as("엄마가 실제로 다녀온 산책을 아빠가 '실수겠지' 하고 지우면 그게 곧 산책 누락이다")
                .containsExactly("엄마가 간 산책");
    }

    @Test
    @DisplayName("다른 가족의 기록 id 는 403 이 아니라 404 다 — id 를 훑어 남의 가족 기록 수를 셀 수 없다")
    void aRecordOfAnotherFamily_isNotFound_notForbidden() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Account neighbor = account("옆집");
        Account neighborsSpouse = account("옆집 배우자");
        Family ours = family(dad, "우리 집", mom);
        Family theirs = family(neighbor, "옆집", neighborsSpouse);
        long theirRecord = body(postCare(neighbor, theirs.groupId(), "meal", "옆집 밥")
                .andExpect(status().isCreated())).path("id").asLong();

        // 내 그룹 경로로 남의 기록 id 를 찍는다 — 내 그룹의 멤버라 인가는 통과한다
        deleteCare(dad, ours.groupId(), theirRecord)
                .andExpect(status().isNotFound());
        // 남의 그룹 경로는 멤버가 아니라 403 — 기록 존재 여부 이전에 막힌다
        deleteCare(dad, theirs.groupId(), theirRecord)
                .andExpect(status().isForbidden());
        assertThat(memos(careLogs(neighbor, theirs.groupId(), null))).containsExactly("옆집 밥");
    }

    @Test
    @DisplayName("탈퇴한 사람의 기록은 아무도 못 지운다 — 본인 판정이 불가능하면 남는 쪽이 안전하다")
    void aWithdrawnMembersRecord_cannotBeDeletedByAnyone() throws Exception {
        Account dad = account("아빠");
        Account mom = account("엄마");
        Family family = family(dad, "한 명이 탈퇴한 집", mom);
        long momsMeal = body(postCare(mom, family.groupId(), "meal", "엄마가 준 밥")
                .andExpect(status().isCreated())).path("id").asLong();
        mockMvc.perform(delete("/auth/me").header("Authorization", "Bearer " + mom.token()))
                .andExpect(status().isNoContent());

        deleteCare(dad, family.groupId(), momsMeal).andExpect(status().isForbidden());

        assertThat(memos(careLogs(dad, family.groupId(), null)))
                .as("done_by 가 SET NULL 로 비어도 '오늘 누군가 밥을 줬다' 는 사실은 남는다")
                .containsExactly("엄마가 준 밥");
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

    private ResultActions deleteCare(Account account, long groupId, long careLogId) throws Exception {
        return mockMvc.perform(delete("/api/groups/{id}/care-logs/{careLogId}", groupId, careLogId)
                .header("Authorization", "Bearer " + account.token()));
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
                // 컬럼 값은 서비스 존의 벽시계다 — JVM 기본 존으로 넣으면 CI 에서 하루가 밀린다.
                .occurredAt(LocalDateTime.now(ClockConfig.SERVICE_ZONE).minusDays(1))
                .memo(memo)
                .build());
    }

    /**
     * 그 방의 그 사람에게 {@code removed_at} 을 찍는다 — 강퇴/나가기가 실제로 하는 일이다.
     *
     * <p>공개 경로로 하지 않는 것은 <b>그 경로가 아직 없기 때문</b>이다(강퇴는 M2.6). 그렇다고
     * 그때까지 이 판정을 안 잠그면, 그 이슈가 이 경로를 건드릴 때 이미 새고 있는 상태로
     * 들어간다. 행을 만들지는 않고 이미 공개 경로로 만들어진 행 하나를 고칠 뿐이다.
     *
     * @return 갱신된 행 수. 1 이 아니면 픽스처가 틀린 것이다
     */
    private int stampRemovedAt(long roomId, long userId) {
        return jdbc.update(
                "UPDATE chat_room_member SET removed_at = ? WHERE room_id = ? AND user_id = ?",
                LocalDateTime.now(ClockConfig.SERVICE_ZONE), roomId, userId);
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
