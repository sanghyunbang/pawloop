package com.heattrip.heat_trip_backend.S3.media.error;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.observability.logging.CorrelationIdFilter;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.context.annotation.Bean;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * 컨트롤러가 정한 상태 코드가 응답까지 살아서 도착하는지 본다 — 이슈 #44.
 *
 * <h2>무엇이 문제였나</h2>
 * <p>{@link GlobalExceptionHandler} 의 {@code @ExceptionHandler(Exception.class)} 가
 * {@link ResponseStatusException} 을 먼저 잡아서, <b>401·403·404 를 의도한 코드가 전부
 * 500 으로 나가고 있었다.</b> 앱은 "권한 없음"과 "서버 고장"을 구분할 수 없었고,
 * 계약(openapi.yaml)이 선언한 응답 코드는 지켜지지 않았다.
 *
 * <h2>왜 단위 테스트로는 안 되는가</h2>
 * <p>핸들러 메서드를 직접 호출하면 언제나 올바른 값이 나온다. 문제는 <b>어느 핸들러가
 * 선택되는가</b>이고, 그건 살아 있는 {@code ExceptionHandlerExceptionResolver} 만이 답한다.
 * 이슈 #5 에서 같은 함정을 실측으로 확인했다 — 구체 핸들러를 별도 advice 클래스에 두면
 * 예외 구체성이 아니라 advice 빈 순서로 승자가 정해져 500 이 그대로 나간다.
 *
 * <p>그래서 실제 요청을 필터 체인부터 태운다. 던지는 쪽은 {@link Probe} 컨트롤러다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class GlobalExceptionHandlerStatusTest extends AbstractMySqlIntegrationTest {

    /** 상태 코드만 던지는 시험용 엔드포인트. 테스트 컨텍스트에만 등록된다. */
    @RestController
    static class Probe {
        static final String BASE = "/__probe/status";

        @GetMapping(BASE + "/401")
        void unauthorized() {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "probe-unauthorized");
        }

        @GetMapping(BASE + "/403")
        void forbidden() {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "probe-forbidden");
        }

        @GetMapping(BASE + "/404")
        void notFound() {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "probe-not-found");
        }

        /** 예상하지 못한 예외 — 500 경로. 메시지에 민감한 값이 섞인 상황을 흉내낸다. */
        @GetMapping(BASE + "/boom")
        void boom() {
            throw new IllegalStateException("bori@example.com 의 비밀번호는 $2a$10$secrethash 다");
        }

        /** 검증 실패 경로 — 400 + code VALIDATION 이어야 한다. (이슈 #10) */
        @GetMapping(BASE + "/illegal-argument")
        void illegalArgument() {
            throw new IllegalArgumentException("probe-validation-failed");
        }

        /**
         * 경로 변수와 질의 파라미터의 <b>타입</b> — 숫자를 선언한 자리에 글자가 오는 경우.
         *
         * <p>메서드 본문에 아무것도 없는 것이 요점이다. 여기까지 오지도 못하고 스프링의
         * 바인딩이 {@code MethodArgumentTypeMismatchException} 을 던진다(#79).
         */
        @GetMapping(BASE + "/typed/{id}")
        void typed(@PathVariable long id, @RequestParam(required = false) Long cursor) {
            // 바인딩만 본다.
        }

        /** 없으면 안 되는 파라미터 — {@code MissingServletRequestParameterException} 자리다. */
        @GetMapping(BASE + "/required-param")
        void requiredParam(@RequestParam long cursor) {
            // 바인딩만 본다.
        }

        /**
         * {@code @Valid @RequestBody} 위반 — {@code MethodArgumentNotValidException} 자리다.
         *
         * <p>이 핸들러가 없던 동안 <b>500</b> 이 나갔다(#145 에서 실측). 저장소에 이미
         * {@code POST /api/explore/feedback} 이 같은 조합을 쓰고 있어서
         * ({@code ExploreController} · {@code FeedbackRequestDto} 의 {@code @NotBlank}),
         * 그 경로가 잘못된 본문에 500 을 답하고 있었다.
         */
        @PostMapping(BASE + "/valid-body")
        void validBody(@Valid @RequestBody ProbeBody body) {
            // 바인딩만 본다.
        }
    }

    /** 우리가 쓴 한글 메시지와 Bean Validation 기본 문구를 한 번에 본다. */
    record ProbeBody(
            @NotBlank(message = "이름을 입력해 주세요.") String named,
            @NotBlank String unnamed) {
    }

    @TestConfiguration
    static class ProbeConfig {
        @Bean
        Probe statusProbe() {
            return new Probe();
        }
    }

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;

    /** 인가 계층을 통과해 컨트롤러까지 도달시키기 위한 토큰. */
    private String bearer() {
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("probe-caller@example.com")
                .name("보리")
                .build());
        return "Bearer " + jwtProvider.createAccessToken(user.getId(), user.getRole());
    }

    @Test
    @DisplayName("컨트롤러가 던진 401·403·404 가 500 이 아니라 그대로 나간다")
    void responseStatusException_keepsItsStatus() throws Exception {
        String token = bearer();

        for (int expected : new int[] {401, 403, 404}) {
            var response = mockMvc
                    .perform(get(Probe.BASE + "/" + expected).header("Authorization", token))
                    .andReturn().getResponse();

            assertThat(response.getStatus())
                    .as("%d 을 의도했는데 %d 가 나왔다 — catch-all 이 먼저 잡으면 500 이 된다 (#44)",
                            expected, response.getStatus())
                    .isEqualTo(expected);
        }
    }

    @Test
    @DisplayName("던진 쪽이 고른 사유 문구가 계약의 error.message 자리에 그대로 실린다")
    void responseStatusException_carriesItsReason() throws Exception {
        var response = mockMvc
                .perform(get(Probe.BASE + "/403").header("Authorization", bearer()))
                .andReturn().getResponse();

        // getReason() 은 던진 사람이 고른 문구다. getMessage() 는 상태 코드가 섞인 조합이라
        // 그대로 내보내면 "403 FORBIDDEN \"probe-forbidden\"" 같은 값이 클라이언트에 간다.
        assertThat(errorBody(response).path("message").asText()).isEqualTo("probe-forbidden");
        assertThat(response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8))
                .doesNotContain("403 FORBIDDEN");
    }

    @Test
    @DisplayName("오류 본문은 상태 코드마다 계약의 Error 봉투와 정해진 code 로 나간다")
    void errorBody_matchesTheContractEnvelope() throws Exception {
        // 예전에는 {status, error, message, path, timestamp} 였다. 계약(openapi.yaml 의
        // Error)은 {error:{code,message,traceId}} 이고, 앱은 error.code 로 분기한다.
        // 형태가 다르면 앱은 계약대로 짠 분기에서 아무것도 못 읽는다. (이슈 #10)
        String token = bearer();
        record Case(int status, String code) {}

        for (Case expected : new Case[] {new Case(403, "FORBIDDEN"), new Case(404, "NOT_FOUND")}) {
            var response = mockMvc
                    .perform(get(Probe.BASE + "/" + expected.status()).header("Authorization", token))
                    .andReturn().getResponse();

            assertThat(errorBody(response).path("code").asText())
                    .as("%d 의 error.code", expected.status())
                    .isEqualTo(expected.code());
        }

        var badRequest = mockMvc
                .perform(get(Probe.BASE + "/illegal-argument").header("Authorization", token))
                .andReturn().getResponse();
        assertThat(badRequest.getStatus()).isEqualTo(400);
        assertThat(errorBody(badRequest).path("code").asText())
                .as("완료 조건 5 가 이 값을 이름으로 요구한다")
                .isEqualTo("VALIDATION");
    }

    @Test
    @DisplayName("오류 본문의 traceId 가 응답 헤더의 상관관계 ID 와 같아서 그 요청을 로그에서 집을 수 있다")
    void errorBody_carriesTheCorrelationIdOfThisRequest() throws Exception {
        // 예전에는 이 값이 message 안에 "(요청 ID: ...)" 로 섞여 있었다. 계약은 그것을
        // error.traceId 라는 자기 필드로 정의한다 — 문구를 파싱해 꺼낼 필요가 없어야 한다.
        var response = mockMvc
                .perform(get(Probe.BASE + "/boom").header("Authorization", bearer()))
                .andReturn().getResponse();

        String traceId = errorBody(response).path("traceId").asText();
        assertThat(traceId).isNotBlank();
        assertThat(traceId)
                .as("헤더와 본문이 다른 값이면 로그에서 이 요청을 찾을 수 없다")
                .isEqualTo(response.getHeader(CorrelationIdFilter.HEADER));
    }

    @Test
    @DisplayName("알 수 없는 경로는 500 이 아니라 404 다")
    void unknownPath_is404() throws Exception {
        // Spring 이 던지는 NoResourceFoundException 은 ResponseStatusException 의 하위 타입이 **아니다**
        // (ServletException 을 상속하고 ErrorResponse 를 구현한다). 핸들러에 타입을 따로 적어야
        // 하고, 안 적으면 catch-all 이 잡아 500 이 된다 — 실제로 그랬다.
        // 인증을 통과시켜야 인가 계층의 401 이 아니라 디스패처까지 온다.
        var response = mockMvc
                .perform(get("/__no-such-path-exists").header("Authorization", bearer()))
                .andReturn().getResponse();

        assertThat(response.getStatus())
                .as("알 수 없는 경로가 500 이면 클라이언트가 '서버 고장'으로 오해한다")
                .isEqualTo(404);
    }

    @Test
    @DisplayName("500 응답 본문에 예외 메시지가 실리지 않는다 — 이메일·해시가 새어 나가던 경로다")
    void internalError_neverEchoesTheExceptionMessage() throws Exception {
        var response = mockMvc
                .perform(get(Probe.BASE + "/boom").header("Authorization", bearer()))
                .andReturn().getResponse();
        String body = response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8);

        assertThat(response.getStatus()).isEqualTo(500);
        assertThat(body)
                .as("예상하지 못한 예외의 메시지에는 SQL 조각·경로·이메일·토큰이 섞여 들어온다 (#6)")
                .doesNotContain("bori@example.com")
                .doesNotContain("$2a$10$secrethash")
                .doesNotContain("IllegalStateException");
        assertThat(errorBody(response).path("code").asText()).isEqualTo("INTERNAL");
        assertThat(errorBody(response).path("traceId").asText())
                .as("원인을 찾을 수단은 남겨야 한다 — 로그에서 이 요청을 집을 수 있는 ID")
                .isNotBlank();
    }

    @Test
    @DisplayName("숫자 자리에 글자가 오면 500 이 아니라 400 VALIDATION 이고, 그 값이 응답에 되실리지 않는다")
    void aTypeMismatchIs400NotInternalError() throws Exception {
        // 저장소 전체의 성질이었다 — /api/chat/rooms/abc/messages 도 ?afterSeq=abc 도
        // /api/groups/abc/care-logs 도 전부 500 이었다(#79 에서 실측). 계약(openapi.yaml)은
        // 그 경로들에 500 을 선언하지 않고, 앱은 500 을 "서버 고장이니 재시도하라" 로 읽는다.
        String token = bearer();
        record Case(String label, String uri) { }

        for (Case probe : new Case[] {
                new Case("경로 변수", Probe.BASE + "/typed/abc"),
                new Case("질의 파라미터", Probe.BASE + "/typed/1?cursor=abc"),
                new Case("long 범위를 넘는 수", Probe.BASE + "/typed/1?cursor=99999999999999999999"),
                new Case("필수 파라미터 누락", Probe.BASE + "/required-param")}) {

            var response = mockMvc.perform(get(probe.uri()).header("Authorization", token))
                    .andReturn().getResponse();

            assertThat(response.getStatus())
                    .as("%s 가 %d 로 나갔다 — handleMalformedRequest 의 타입 목록에서 "
                            + "MethodArgumentTypeMismatchException 을 빼면 다시 500 이 된다",
                            probe.label(), response.getStatus())
                    .isEqualTo(400);
            assertThat(errorBody(response).path("code").asText()).isEqualTo("VALIDATION");
            assertThat(errorBody(response).path("message").asText())
                    .as("""
                            예외 메시지에는 들어온 값이 그대로 섞여 있다 — 실제로 \
                            'For input string: "abc"' 가 들어 있었다 (#6). 고정 문구여야 한다.""")
                    .doesNotContain("abc")
                    .doesNotContain("cursor")
                    .doesNotContain("99999999999999999999");
        }
    }

    @Test
    @DisplayName("@Valid @RequestBody 위반이 500 이 아니라 400 VALIDATION 이고, 우리가 쓴 문구로 나간다")
    void invalidBody_isBadRequestNotServerError() throws Exception {
        MockHttpServletResponse response = mockMvc.perform(
                        post(Probe.BASE + "/valid-body")
                                .header("Authorization", bearer())
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"named\":\"  \",\"unnamed\":\"  \"}"))
                .andReturn().getResponse();

        assertThat(response.getStatus())
                .as("""
                        MethodArgumentNotValidException 에 핸들러가 없던 동안 catch-all 이 잡아 \
                        500 이 나갔다(#145 실측). 저장소의 POST /api/explore/feedback 이 이미 \
                        같은 조합을 쓰고 있어서 그 경로가 잘못된 본문에 500 을 답하고 있었다.""")
                .isEqualTo(400);
        assertThat(errorBody(response).path("code").asText()).isEqualTo("VALIDATION");

        String message = errorBody(response).path("message").asText();
        assertThat(message)
                .as("우리가 message 를 적어 둔 제약이 있으면 그것을 쓴다")
                .isEqualTo("이름을 입력해 주세요.");
        assertThat(message)
                .as("""
                        Bean Validation 기본 문구는 영어이고, @Size 같은 것은 들어온 값의 \
                        길이를 문구에 섞는 구현이 있다 — 내보내지 않는다 (#6).""")
                .doesNotContain("must not be blank");
    }

    @Test
    @DisplayName("우리가 쓴 문구가 하나도 없으면 고정 문구로 답한다 — 영어 기본 문구가 새지 않는다")
    void invalidBody_withoutOurMessage_fallsBackToAFixedPhrase() throws Exception {
        MockHttpServletResponse response = mockMvc.perform(
                        post(Probe.BASE + "/valid-body")
                                .header("Authorization", bearer())
                                .contentType(MediaType.APPLICATION_JSON)
                                .content("{\"named\":\"보리\",\"unnamed\":\"  \"}"))
                .andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(400);
        assertThat(errorBody(response).path("message").asText())
                .isEqualTo("요청 값이 올바르지 않습니다.");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 응답 본문의 계약 봉투 안쪽({@code $.error})을 꺼낸다. */
    private static JsonNode errorBody(MockHttpServletResponse response) throws Exception {
        JsonNode root = MAPPER.readTree(
                response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8));

        assertThat(root.has("error"))
                .as("계약(openapi.yaml 의 Error)은 최상위에 error 하나뿐인 봉투다. 본문: %s", root)
                .isTrue();
        assertThat(root.properties())
                .as("봉투 밖에 필드를 더하면 그건 더 이상 계약의 Error 가 아니다")
                .hasSize(1);
        return root.path("error");
    }
}
