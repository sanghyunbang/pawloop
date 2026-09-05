package com.heattrip.heat_trip_backend.dog;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import com.heattrip.heat_trip_backend.dog.service.DogService;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 반려동물 프로필을 <b>HTTP 로</b> 확인한다 — 이슈 #145 완료 조건 4.
 *
 * <h2>왜 통합 테스트여야 하는가</h2>
 * <p>이 도메인에서 틀리면 아픈 것은 <b>인가</b>다. "남의 반려동물이 안 보인다" 는
 * 서비스의 쿼리 필터 · {@code @CurrentUser} 해석 · 전역 예외 처리기의 상태 코드 셋이 함께
 * 맞아야 성립한다. 서비스만 불러 보면 셋 중 하나가 빠져도 초록불이 난다 —
 * {@code ResponseStatusException(404)} 은 전역 처리기에 분기가 없으면 <b>500</b> 으로 나가고,
 * 그건 단위 테스트에서 정의상 안 보인다({@code CareSharingIntegrationTest} 가 같은 이유를
 * 적어 뒀다).
 *
 * <p>애너테이션이 두 줄뿐인 것은 <b>의도다</b> — {@code CareSharingIntegrationTest} ·
 * {@code FamilyGroupInviteIntegrationTest} 와 글자 그대로 같아야 스프링 컨텍스트 캐시를
 * 공유한다(#21). {@code @Transactional} 을 붙이지 않는 것도 같다: 이 테스트는 "다른
 * 계정이 <b>다음 요청에서</b> 무엇을 보는가" 를 보는데, 테스트가 트랜잭션을 감싸면 커밋되지
 * 않은 것을 같은 트랜잭션 안에서 보는 셈이라 검증이 공허해진다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class DogIntegrationTest extends AbstractMySqlIntegrationTest {

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
    private JdbcTemplate jdbc;

    // ─────────────────── 완료 조건 4 — 개와 고양이를 둘 다 등록할 수 있다 ───────────────────

    @Test
    @DisplayName("고양이를 등록할 수 있다 — species 가 없으면 고양이를 키우는 사람은 산책을 붙일 곳이 없다")
    void registersACat() throws Exception {
        Account me = account("집사");

        JsonNode cat = body(register(me, """
                {"name":"나비","species":"cat","size":"small","neutered":true}
                """).andExpect(status().isCreated()));

        assertThat(cat.path("species").asText())
                .as("계약이 정한 소문자 그대로 나가야 한다 — CAT 으로 나가면 앱의 PetSpecies 가 못 읽는다")
                .isEqualTo("cat");
        assertThat(cat.path("name").asText()).isEqualTo("나비");
        assertThat(cat.path("neutered").asBoolean()).isTrue();
        assertThat(cat.path("id").asLong()).isPositive();
    }

    @Test
    @DisplayName("species 를 안 보내면 개다 — 이 필드가 없던 때 만들어진 앱이 그대로 동작한다")
    void defaultsToDog() throws Exception {
        Account me = account("보리아빠");

        JsonNode dog = body(register(me, """
                {"name":"보리","size":"medium"}
                """).andExpect(status().isCreated()));

        assertThat(dog.path("species").asText()).isEqualTo("dog");
        assertThat(dog.path("neutered").asBoolean())
                .as("계약이 default: false 로 선언했다")
                .isFalse();
        assertThat(dog.path("breed").isNull())
                .as("품종을 모르면 null 이다 — 빈 문자열과 나누지 않는다")
                .isTrue();
    }

    @Test
    @DisplayName("계약 밖의 종·몸집은 400 이다 — 응답 본문에 입력값을 되싣지 않는다")
    void rejectsValuesOutsideTheContract() throws Exception {
        Account me = account("아무개");

        String speciesError = register(me, """
                {"name":"보리","species":"dragon","size":"small"}
                """)
                .andExpect(status().isBadRequest())
                .andReturn().getResponse().getContentAsString();

        assertThat(speciesError)
                .as("허용 목록은 계약에 이미 공개된 값이라 알려 준다")
                .contains("dog", "cat", "other");
        assertThat(speciesError)
                .as("입력값을 되실으면 그것이 그대로 응답 본문이 된다 (#6)")
                .doesNotContain("dragon");

        register(me, """
                {"name":"보리","size":"gigantic"}
                """).andExpect(status().isBadRequest());

        register(me, """
                {"name":"보리"}
                """)
                .andExpect(status().isBadRequest());

        register(me, """
                {"name":"   ","size":"small"}
                """).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("미래 생일은 400 이다 — 저장하면 나이가 음수로 나간다")
    void rejectsFutureBirth() throws Exception {
        Account me = account("아무개");

        register(me, """
                {"name":"보리","size":"small","birth":"2099-01-01"}
                """).andExpect(status().isBadRequest());
    }

    // ─────────────────── 소유권 — 남의 것과 없는 것이 같은 404 다 ───────────────────

    @Test
    @DisplayName("남의 반려동물과 없는 반려동물이 구분되지 않는 404 다")
    void othersDogAndMissingDogAreIndistinguishable() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");

        long dogId = body(register(owner, """
                {"name":"보리","size":"small"}
                """).andExpect(status().isCreated())).path("id").asLong();

        String othersDog = detail(stranger, dogId)
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();

        String missingDog = detail(stranger, 999_999_999L)
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();

        // traceId 는 요청마다 다르다 — 그것만 지우고 비교한다. 그 값은 리소스의 존재를
        // 말해 주지 않으므로 두 응답을 구분 가능하게 만들지 않는다.
        assertThat(withoutTraceId(othersDog))
                .as("""
                        403 을 주면 '그 id 는 존재한다' 를 알려 주는 셈이라, id 를 훑어 남이 \
                        반려동물을 몇 마리 키우는지 셀 수 있다. traceId 말고는 같아야 한다.""")
                .isEqualTo(withoutTraceId(missingDog));
    }

    @Test
    @DisplayName("목록에는 내 것만 나온다")
    void listShowsOnlyMine() throws Exception {
        Account me = account("나");
        Account other = account("남");

        register(me, """
                {"name":"보리","size":"small"}
                """).andExpect(status().isCreated());
        register(other, """
                {"name":"남의개","size":"large"}
                """).andExpect(status().isCreated());

        JsonNode mine = body(mockMvc.perform(get("/api/dogs")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk()));

        assertThat(mine.size()).isEqualTo(1);
        assertThat(mine.get(0).path("name").asText()).isEqualTo("보리");
    }

    @Test
    @DisplayName("토큰이 없으면 본문 없는 401 이다 — 이 경로들은 publicMatchers 에 없다")
    void requiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/dogs")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/dogs/1")).andExpect(status().isUnauthorized());
        mockMvc.perform(post("/api/dogs")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"보리\",\"size\":\"small\"}"))
                .andExpect(status().isUnauthorized());
    }

    // ─────────────────── 총량 상한 ───────────────────

    @Test
    @DisplayName("상한을 넘으면 409 다 — rate limit 은 속도를 잴 뿐 총량을 재지 않는다")
    void capsThePetCount() throws Exception {
        Account me = account("다견가정");

        for (int i = 0; i < DogService.MAX_PETS; i++) {
            register(me, """
                    {"name":"%d호","size":"small"}
                    """.formatted(i)).andExpect(status().isCreated());
        }

        register(me, """
                {"name":"한마리더","size":"small"}
                """).andExpect(status().isConflict());
    }

    // ─────────────────── 소프트 삭제 (이슈 #156) ───────────────────

    @Test
    @DisplayName("지우면 목록에서 빠지고 상세는 404 다 — 행은 deleted_at 이 찍힌 채 남는다")
    void deletingHidesTheDogEverywhere() throws Exception {
        Account me = account("보내준 사람");
        long dogId = body(register(me, """
                {"name":"보리","size":"small"}
                """).andExpect(status().isCreated())).path("id").asLong();

        remove(me, dogId).andExpect(status().isNoContent());

        assertThat(list(me).size())
                .as("""
                        세 쿼리 전부 deleted_at is null 을 건다 — 하나만 빠져도 지운 아이가 어딘가에서 \
                        되살아난다(완료 조건 1).""")
                .isZero();
        detail(me, dogId).andExpect(status().isNotFound());
        assertThat(jdbc.queryForObject(
                "select count(*) from dog where id = ? and deleted_at is not null", Integer.class, dogId))
                .as("""
                        물리 삭제가 아니다. walk.fk_walk_dog 가 CASCADE 라 행을 지우면 그 아이의 산책 \
                        이력 전부가 조용히 함께 사라진다 — 사용자는 '프로필만 지웠다' 고 생각한다.""")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("두 번째 삭제는 404 다 — 지운 것은 없는 것과 같다")
    void secondDeleteIsNotFound() throws Exception {
        Account me = account("두번지우는이");
        long dogId = body(register(me, """
                {"name":"탄이","size":"small"}
                """).andExpect(status().isCreated())).path("id").asLong();

        remove(me, dogId).andExpect(status().isNoContent());
        remove(me, dogId).andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("남의 반려동물 삭제는 없는 것과 같은 404 이고, 주인에게는 그대로 있다")
    void othersDogCannotBeDeleted() throws Exception {
        Account owner = account("주인");
        Account stranger = account("남");
        long dogId = body(register(owner, """
                {"name":"구름","size":"small"}
                """).andExpect(status().isCreated())).path("id").asLong();

        String othersDog = remove(stranger, dogId)
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();
        String missingDog = remove(stranger, 999_999_999L)
                .andExpect(status().isNotFound())
                .andReturn().getResponse().getContentAsString();

        assertThat(withoutTraceId(othersDog)).isEqualTo(withoutTraceId(missingDog));
        detail(owner, dogId).andExpect(status().isOk());
    }

    @Test
    @DisplayName("지운 아이는 상한에 안 센다 — 20마리를 채운 뒤 하나를 보내면 한 마리 더 들일 수 있다")
    void deletedDogsDoNotCountTowardTheCap() throws Exception {
        Account me = account("다견가정");
        long first = body(register(me, """
                {"name":"0호","size":"small"}
                """).andExpect(status().isCreated())).path("id").asLong();
        for (int i = 1; i < DogService.MAX_PETS; i++) {
            register(me, """
                    {"name":"%d호","size":"small"}
                    """.formatted(i)).andExpect(status().isCreated());
        }
        register(me, """
                {"name":"한마리더","size":"small"}
                """).andExpect(status().isConflict());

        remove(me, first).andExpect(status().isNoContent());

        register(me, """
                {"name":"한마리더","size":"small"}
                """).andExpect(status().isCreated());
    }

    @Test
    @DisplayName("소프트 삭제된 아이가 있어도 탈퇴는 된다 — 완료 조건 4. fk_dog_user 의 CASCADE 가 그 행도 지운다")
    void withdrawalStillWorksWithASoftDeletedDog() throws Exception {
        Account me = account("떠나는 사람");
        long dogId = body(register(me, """
                {"name":"감자","size":"small"}
                """).andExpect(status().isCreated())).path("id").asLong();
        remove(me, dogId).andExpect(status().isNoContent());

        mockMvc.perform(delete("/auth/me").header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNoContent());

        assertThat(jdbc.queryForObject("select count(*) from dog where id = ?", Integer.class, dogId))
                .as("탈퇴는 users 하드 삭제다 — 소프트 삭제된 행도 CASCADE 로 따라 지워진다")
                .isZero();
    }

    // ─────────────────── 파생값 ───────────────────

    @Test
    @DisplayName("생일이 없으면 ageMonths 는 null 이다 — 0 은 '갓 태어났다' 라는 다른 뜻이다")
    void ageIsNullWhenBirthIsUnknown() throws Exception {
        Account me = account("아무개");

        JsonNode noBirth = body(register(me, """
                {"name":"보리","size":"small"}
                """).andExpect(status().isCreated()));

        assertThat(noBirth.path("ageMonths").isNull()).isTrue();

        JsonNode withBirth = body(register(me, """
                {"name":"콩이","size":"small","birth":"2024-01-15"}
                """).andExpect(status().isCreated()));

        assertThat(withBirth.path("ageMonths").asInt())
                .as("2024-01-15 생이면 지금은 최소 열 달은 넘었다")
                .isGreaterThan(10);
    }

    // ─────────────────── 지그 ───────────────────

    /** 요청마다 달라지는 값 하나를 지운다. 나머지가 같아야 두 응답이 구분되지 않는다. */
    private static String withoutTraceId(String body) {
        return body.replaceAll("\"traceId\":\"[^\"]*\"", "\"traceId\":\"·\"");
    }

    private ResultActions register(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/dogs")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private ResultActions detail(Account account, long dogId) throws Exception {
        return mockMvc.perform(get("/api/dogs/{dogId}", dogId)
                .header("Authorization", "Bearer " + account.token()));
    }

    private ResultActions remove(Account account, long dogId) throws Exception {
        return mockMvc.perform(delete("/api/dogs/{dogId}", dogId)
                .header("Authorization", "Bearer " + account.token()));
    }

    private JsonNode list(Account account) throws Exception {
        return body(mockMvc.perform(get("/api/dogs")
                        .header("Authorization", "Bearer " + account.token()))
                .andExpect(status().isOk()));
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("dog-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
