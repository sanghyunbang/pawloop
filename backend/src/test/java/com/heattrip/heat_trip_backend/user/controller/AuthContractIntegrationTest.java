package com.heattrip.heat_trip_backend.user.controller;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * {@code /auth} 표면이 계약({@code docs/04-api/openapi.yaml})과 <b>실제로</b> 같은지 끝까지
 * 돌려 본다 — 이슈 #10.
 *
 * <h2>왜 통합인가</h2>
 * <p>이 이슈가 고치는 것은 "코드가 계약과 다른 말을 한다" 이고, 그 어긋남은 세 계층에 흩어져
 * 있었다: 컨트롤러의 반환 타입, 전역 예외 처리기의 본문 형태, Security 의 인가 경계. 목을 쓰는
 * 슬라이스 테스트는 정의상 이걸 못 잡는다 — 각 계층의 가정을 스텁이 따로따로 만족시켜 준다.
 * 특히 <b>어느 예외 핸들러가 이기는가</b>는 살아 있는
 * {@code ExceptionHandlerExceptionResolver} 만이 답한다(#44 에서 실측).
 *
 * <p><b>{@code @Transactional} 을 붙이지 않은 것은 의도다.</b> 아래
 * {@code 로그인_응답의_refresh토큰은_실제로_갱신에_쓸_수_있다} 는 로그인이 저장한 RT 행이
 * <b>커밋되어 다음 요청에서 보이는지</b>를 확인한다. 테스트 트랜잭션 하나로 묶으면 그 확인이
 * 무의미해진다. 대신 만든 행을 {@code @AfterEach} 가 직접 지운다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄뿐인 것도 의도다 —
 * {@code AuthTokenRefreshIntegrationTest}·{@code AuthEndpointAuthorizationTest} 와 글자 그대로
 * 같아야 스프링 컨텍스트 캐시를 공유한다(#21 §5).
 */
@SpringBootTest
@AutoConfigureMockMvc
class AuthContractIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** 이 클래스가 만드는 계정의 이메일 접두어. 다른 테스트의 행과 섞이지 않게 한다. */
    private static final String EMAIL_PREFIX = "auth-contract-";

    private static final String PASSWORD = "test1234!";

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private RefreshTokenRepository refreshTokenRepository;
    @Autowired private JWTProvider jwtProvider;

    /** 트랜잭션 롤백에 기대지 않으므로 만든 행을 직접 지운다. */
    private final List<String> createdEmails = new ArrayList<>();

    @AfterEach
    void cleanUp() {
        for (String email : createdEmails) {
            userRepository.findByEmail(email).ifPresent(user -> {
                refreshTokenRepository.deleteByUserId(user.getId());
                userRepository.delete(user);
            });
        }
        createdEmails.clear();
    }

    // ─────────────────── 로그인 응답 (완료 조건 1·2·9) ───────────────────

    @Test
    @DisplayName("로그인 응답이 계약의 AuthTokens JSON 이며 accessToken·refreshToken·expiresIn·isNew·user 를 모두 싣는다")
    void 로그인_응답은_계약의_AuthTokens_JSON_이다() throws Exception {
        // 예전에는 본문이 JWT 평문 문자열 하나였고, #9 가 발급·저장한 refresh 토큰은 실을
        // 자리가 없어 아무에게도 전달되지 않았다. 반환 타입을 ResponseEntity<String> 으로
        // 되돌리면 아래 JSON 경로 단언이 전부 죽는다 (완료 조건 9).
        String email = signup("tokens");

        MockHttpServletResponse response = login(email, PASSWORD);

        assertThat(response.getStatus()).isEqualTo(200);
        JsonNode body = json(response);

        assertThat(body.path("accessToken").asText())
                .as("JWT 는 항상 eyJ 로 시작한다(base64url 로 적은 {\"alg\")")
                .startsWith("eyJ");
        assertThat(body.path("refreshToken").asText())
                .as("패딩 없는 Base64URL 32바이트는 정확히 43자다")
                .hasSize(43);
        assertThat(body.path("expiresIn").asLong())
                .as("실제 토큰 수명(jwt.expiration)에서 계산한 초여야 한다 (완료 조건 2)")
                .isEqualTo(jwtProvider.getExpiresInSeconds())
                .isEqualTo(3600L);
        assertThat(body.path("isNew").asBoolean())
                .as("이미 있는 계정으로 들어오는 경로다")
                .isFalse();
        assertThat(body.path("user").path("id").asLong()).isPositive();
        assertThat(body.path("user").path("email").asText()).isEqualTo(email);
        assertThat(body.path("user").path("provider").asText())
                .as("이메일 가입은 local 이다 — 계약 User.provider enum 의 값")
                .isEqualTo("local");
        assertThat(body.path("user").has("nickname")).isTrue();
    }

    @Test
    @DisplayName("로그인 응답의 refresh 토큰은 실제로 갱신에 쓸 수 있다 — 원장에 남은 행과 같은 값이다")
    void 로그인_응답의_refresh토큰은_실제로_갱신에_쓸_수_있다() throws Exception {
        // "필드가 있다" 로는 부족하다. 형태만 맞고 원장에 없는 값을 실어도 위 테스트는 통과한다.
        // 그 값으로 실제 회전이 되는지가 이 이슈가 고치려던 것이다.
        String email = signup("usable-rt");
        String refreshToken = json(login(email, PASSWORD)).path("refreshToken").asText();

        MockHttpServletResponse rotated = mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + refreshToken + "\"}"))
                .andReturn().getResponse();

        assertThat(rotated.getStatus())
                .as("401 이면 로그인이 실어 보낸 값이 원장의 그 값이 아니라는 뜻이다")
                .isEqualTo(200);
        assertThat(json(rotated).path("refreshToken").asText())
                .as("갱신은 회전이다 — 같은 값을 다시 주지 않는다")
                .isNotEqualTo(refreshToken);
        assertThat(json(rotated).has("isNew"))
                .as("갱신에 '새로 가입했는가' 는 의미가 없다 — 계약이 선택 필드로 둔 이유다")
                .isFalse();
    }

    @Test
    @DisplayName("자격증명이 틀린 로그인은 500 도 400 도 아니고 본문 없는 401 이다")
    void 자격증명_실패는_본문_없는_401_이다() throws Exception {
        // 예전에는 IllegalAccessException(checked)이 catch-all 에 잡혀 500 이었다.
        // 앱은 '비밀번호가 틀렸다' 와 '서버가 죽었다' 를 구분할 수 없었다 (완료 조건 7).
        String email = signup("bad-credentials");

        MockHttpServletResponse response = login(email, "wrong-password");

        assertThat(response.getStatus()).isEqualTo(401);
        assertThat(response.getContentAsString(StandardCharsets.UTF_8))
                .as("계약의 Unauthorized 는 본문을 선언하지 않는다 (#5)")
                .isEmpty();

        MockHttpServletResponse unknown = login("nobody-" + email, PASSWORD);
        assertThat(unknown.getStatus())
                .as("가입 여부가 응답 코드로 새어 나가면 그 자체가 조회 수단이다 (#6)")
                .isEqualTo(401);
    }

    // ─────────────────── 회원가입 (계약: 201 + User · 409) ───────────────────

    @Test
    @DisplayName("회원가입은 200 + 평문이 아니라 201 + 계약의 User 를 반환한다")
    void 회원가입은_201과_User_를_반환한다() throws Exception {
        String email = EMAIL_PREFIX + "created@example.com";
        createdEmails.add(email);

        MockHttpServletResponse response = signupRequest(email);

        assertThat(response.getStatus()).isEqualTo(201);
        JsonNode body = json(response);
        assertThat(body.path("id").asLong())
                .as("예전 응답은 평문 \"회원가입 성공\" 이라 방금 만든 계정의 id 조차 알 수 없었다")
                .isPositive();
        assertThat(body.path("email").asText()).isEqualTo(email);
        assertThat(body.path("provider").asText()).isEqualTo("local");
        assertThat(body.has("password"))
                .as("계약의 User 에 password 는 없다. 있으면 그건 유출이다")
                .isFalse();
    }

    @Test
    @DisplayName("이미 가입된 이메일로 다시 가입하면 400 이 아니라 409 이고 본문은 계약의 Error 다")
    void 중복_가입은_409_와_계약의_Error_다() throws Exception {
        String email = signup("duplicate");

        MockHttpServletResponse response = signupRequest(email);

        assertThat(response.getStatus()).isEqualTo(409);
        assertThat(errorBody(response).path("code").asText()).isEqualTo("CONFLICT");
        assertThat(response.getContentAsString(StandardCharsets.UTF_8))
                .as("사유 문구는 그대로 본문이 된다 — 이메일을 되싣으면 그게 유출이다 (#6)")
                .doesNotContain(email);
    }

    // ─────────────────── /auth/oauth/{provider} (완료 조건 4·5·11) ───────────────────

    @Test
    @DisplayName("지원 공급자로 소셜 로그인을 시작하면 302 와 Location: /oauth2/authorization/{provider} 를 받는다")
    void 소셜_로그인_시작은_302_래퍼다() throws Exception {
        // 예전에는 이 경로가 빈 200 이었고, 계약은 "미구현" 이라고 적었다 (완료 조건 4).
        //
        // naver 는 여기 있었다. ADR-0010 이 보류로 확정하면서 계약 enum 과
        // AuthController.SUPPORTED_PROVIDERS 에서 함께 빠졌다(#15). 아래
        // 화이트리스트_밖_공급자는_400_이다 가 그 자리를 이어받는다.
        for (String provider : new String[] {"kakao", "google", "apple"}) {
            MockHttpServletResponse response = mockMvc.perform(get("/auth/oauth/" + provider))
                    .andReturn().getResponse();

            assertThat(response.getStatus())
                    .as("%s 는 계약 enum 에 있는 공급자다", provider)
                    .isEqualTo(302);
            assertThat(response.getHeader("Location"))
                    .isEqualTo("/oauth2/authorization/" + provider);
        }
    }

    @Test
    @DisplayName("계약 enum 에 없는 공급자는 302 가 아니라 400 이고 error.code 가 VALIDATION 이다")
    void 화이트리스트_밖_공급자는_400_이다() throws Exception {
        // 화이트리스트 검사를 지우면 여기가 302 를 받아 빨간불이 된다 (완료 조건 11).
        MockHttpServletResponse response = mockMvc.perform(get("/auth/oauth/facebook"))
                .andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(400);
        assertThat(errorBody(response).path("code").asText()).isEqualTo("VALIDATION");
        assertThat(errorBody(response).path("traceId").asText())
                .as("오류를 신고할 때 서버 로그에서 이 요청을 집을 수단")
                .isNotBlank();
        assertThat(response.getContentAsString(StandardCharsets.UTF_8))
                .as("입력값을 본문에 되싣으면 반사형 XSS 재료가 된다")
                .doesNotContain("facebook");
    }

    @Test
    @DisplayName("보류된 공급자 naver 도 이 래퍼에서는 400 이다 — ADR-0010")
    void 보류된_공급자_naver_는_400_이다() throws Exception {
        // ADR-0010 이 네이버를 보류로 확정했다. 계약 enum 에서 빼면서 코드 화이트리스트도
        // 같이 좁혔다 — 한쪽만 좁히면 계약이 광고하지 않는 값이 302 로 통과한다.
        //
        // 이것으로 네이버 로그인이 막히지는 **않는다.** 앱이 실제로 여는 것은 이 래퍼가 아니라
        // /oauth2/authorization/naver 이고, 클라이언트 등록은 아직 살아 있다. 그 구멍은 #13 소유다.
        MockHttpServletResponse response = mockMvc.perform(get("/auth/oauth/naver"))
                .andReturn().getResponse();

        assertThat(response.getStatus())
                .as("naver 를 화이트리스트에 되돌리면 여기가 302 를 받아 빨간불이 된다")
                .isEqualTo(400);
        assertThat(errorBody(response).path("code").asText()).isEqualTo("VALIDATION");
    }

    // ─────────────────── /auth/me (완료 조건 3·6) ───────────────────

    @Test
    @DisplayName("내 정보 조회가 계약의 User 스키마를 그대로 반환하고 비밀번호는 싣지 않는다")
    void 내_정보_조회는_계약의_User_를_반환한다() throws Exception {
        String email = signup("me");
        String accessToken = json(login(email, PASSWORD)).path("accessToken").asText();

        MockHttpServletResponse response = mockMvc.perform(get("/auth/me")
                        .header("Authorization", "Bearer " + accessToken))
                .andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(200);
        JsonNode body = json(response);

        // 계약(components/schemas/User)의 속성 이름과 1:1 이다.
        assertThat(fieldNames(body))
                .containsExactlyInAnyOrder("id", "email", "name", "nickname", "gender",
                        "age", "travelType", "imageUrl", "provider", "createdAt", "updatedAt");
        assertThat(body.path("email").asText()).isEqualTo(email);
        assertThat(body.path("provider").asText())
                .as("users.provider 컬럼은 #7 에서 생겼다 — '내려오지 않는다' 는 서술은 낡았다")
                .isEqualTo("local");
        assertThat(body.has("isNew"))
                .as("isNew 는 로그인 1회성 이벤트 속성이지 프로필의 영속 속성이 아니다 (#23)")
                .isFalse();
    }

    @Test
    @DisplayName("잘못된 토큰으로 내 정보를 조회하면 500 이 아니라 본문 없는 401 이다")
    void 무효한_토큰의_내_정보_조회는_본문_없는_401_이다() throws Exception {
        // 완료 조건 6. 이슈 본문은 여기 {"error":{"code":"UNAUTHORIZED"}} 본문을 요구했지만,
        // #5 가 그보다 뒤에 '401 은 본문 없음' 으로 확정했고 계약의
        // components/responses/Unauthorized 와 GeneratedOpenApiSpecTest 가 그것을 잠근다.
        // 본문을 다시 붙이면 그 두 곳이 빨간불이 된다 — 상태 코드만 맞춘다.
        MockHttpServletResponse response = mockMvc.perform(get("/auth/me")
                        .header("Authorization", "Bearer not-a-real-token"))
                .andReturn().getResponse();

        assertThat(response.getStatus())
                .as("예전에는 이 경로가 500 이었다 — 앱은 갱신할 때인지 서버가 죽은 것인지 몰랐다")
                .isEqualTo(401);
        assertThat(response.getContentAsString(StandardCharsets.UTF_8)).isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 계정을 하나 만들고 그 이메일을 돌려준다. 정리 목록에 등록된다. */
    private String signup(String slug) throws Exception {
        String email = EMAIL_PREFIX + slug + "@example.com";
        createdEmails.add(email);

        assertThat(signupRequest(email).getStatus())
                .as("사전 조건이 깨지면 아래 단언들이 무엇을 보는지 알 수 없다")
                .isEqualTo(201);
        return email;
    }

    private MockHttpServletResponse signupRequest(String email) throws Exception {
        String body = """
                {"email":"%s","password":"%s","nickname":"보리아빠","name":"보리아빠"}
                """.formatted(email, PASSWORD);

        return mockMvc.perform(post("/auth/signup")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andReturn().getResponse();
    }

    private MockHttpServletResponse login(String email, String password) throws Exception {
        return mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"%s\",\"password\":\"%s\"}".formatted(email, password)))
                .andReturn().getResponse();
    }

    private static JsonNode json(MockHttpServletResponse response) throws Exception {
        return MAPPER.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }

    /** 계약 봉투의 안쪽({@code $.error})을 꺼내면서 봉투 자체의 모양도 확인한다. */
    private static JsonNode errorBody(MockHttpServletResponse response) throws Exception {
        JsonNode root = json(response);

        assertThat(fieldNames(root))
                .as("계약의 Error 는 최상위에 error 하나뿐인 봉투다. 본문: %s", root)
                .containsExactly("error");
        return root.path("error");
    }

    private static List<String> fieldNames(JsonNode node) {
        List<String> names = new ArrayList<>();
        node.fieldNames().forEachRemaining(names::add);
        return names;
    }
}
