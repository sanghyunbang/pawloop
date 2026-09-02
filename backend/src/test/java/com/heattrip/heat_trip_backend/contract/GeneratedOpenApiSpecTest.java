package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;
import org.yaml.snakeyaml.Yaml;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.Set;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * springdoc 이 <b>생성하는</b> OpenAPI({@code /v3/api-docs})가 손으로 쓴 정본과 갈라지지 않는지 본다 — 이슈 #5.
 *
 * <p>왜 필요한가: {@code AuthContractSpecTest} 는 저장소 안의 {@code docs/04-api/openapi.yaml} 만 읽는다.
 * 그런데 앱 팀이 Swagger UI 의 "Try it out" 으로 만지고 클라이언트를 뽑는 대상은 <b>생성본</b>이다.
 * 두 문서가 갈라지면 정본 쪽 테스트는 전부 초록불인 채로 앱만 깨진다.
 *
 * <p>실제로 그런 일이 있었다. {@link com.heattrip.heat_trip_backend.user.CurrentUser} 는
 * springdoc 이 모르는 커스텀 리졸버 파라미터라, 알려 주지 않으면 {@code @ModelAttribute} 처럼 보고
 * <b>required=true 인 query 파라미터</b>(이름 {@code me}/{@code user}, 스키마는 {@code User} 전체)로
 * 문서화한다 — 오퍼레이션 33개가 그렇게 오염됐고(main 에서는 0개였다) 잡는 테스트가 하나도 없었다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄뿐인 것은 의도다 —
 * {@code AuthMeIntegrationTest}·{@code AuthEndpointAuthorizationTest} 와 컨텍스트 캐시를 공유한다.
 * {@code @TestPropertySource} 로 {@code app.security.docs-public} 을 켜지 않고 대신 토큰을 만들어
 * 부르는 것도 같은 이유다(캐시 키가 갈라지면 스프링 컨텍스트가 한 번 더 뜬다).
 *
 * <p>네트워크를 타지 않는다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class GeneratedOpenApiSpecTest extends AbstractMySqlIntegrationTest {

    /** 인증 주체를 주입받는 컨트롤러 파라미터의 이름들. 이 이름이 계약에 파라미터로 나타나면 회귀다. */
    private static final List<String> PRINCIPAL_PARAMETER_NAMES = List.of("me", "user");

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Test
    @DisplayName("생성된 OpenAPI 의 어떤 오퍼레이션에도 인증 주체가 me·user 라는 요청 파라미터로 새어 나오지 않는다")
    void generatedSpec_doesNotExposeThePrincipalAsARequestParameter() throws Exception {
        JsonNode paths = generatedSpec().path("paths");

        List<String> polluted = new ArrayList<>();
        forEachOperation(paths, (operationId, operation) -> {
            for (JsonNode parameter : operation.path("parameters")) {
                if (PRINCIPAL_PARAMETER_NAMES.contains(parameter.path("name").asText())) {
                    polluted.add(operationId + " ← " + parameter.path("name").asText());
                }
            }
        });

        assertThat(polluted)
                .as("@CurrentUser 는 서버가 토큰에서 해석한다. 클라이언트가 보낼 값이 아니고 "
                        + "필수 파라미터로 문서화되면 생성 클라이언트의 시그니처가 전부 틀린다")
                .isEmpty();
    }

    @Test
    @DisplayName("생성된 OpenAPI 의 어떤 요청 파라미터도 User 스키마 전체를 값으로 요구하지 않는다")
    void generatedSpec_neverAsksTheClientToSendAWholeUser() throws Exception {
        JsonNode paths = generatedSpec().path("paths");

        List<String> leaking = new ArrayList<>();
        forEachOperation(paths, (operationId, operation) -> {
            for (JsonNode parameter : operation.path("parameters")) {
                if ("#/components/schemas/User".equals(parameter.path("schema").path("$ref").asText())) {
                    leaking.add(operationId + " ← " + parameter.path("name").asText());
                }
            }
        });

        // 이름을 바꿔 우회하는 회귀(@CurrentUser User principal 등)까지 잡는다.
        assertThat(leaking)
                .as("사용자 엔티티 26개 필드를 쿼리스트링으로 보내라는 계약은 어떤 경우에도 옳지 않다")
                .isEmpty();
    }

    @Test
    @DisplayName("GET /auth/me 는 생성된 계약에서도 요청 파라미터가 하나도 없다")
    void generatedSpec_authMeTakesNoParameters() throws Exception {
        JsonNode authMeGet = generatedSpec().path("paths").path("/auth/me").path("get");

        assertThat(authMeGet.isMissingNode())
                .as("GET /auth/me 가 생성된 계약에 없다면 이 테스트는 아무것도 지키지 못한다")
                .isFalse();

        List<String> parameterNames = new ArrayList<>();
        for (JsonNode parameter : authMeGet.path("parameters")) {
            parameterNames.add(parameter.path("name").asText());
        }

        assertThat(parameterNames)
                .as("주체는 Authorization 헤더에서 온다. 그 밖에 클라이언트가 보낼 것은 없다")
                .isEmpty();
    }

    @Test
    @DisplayName("생성된 계약의 어떤 401 응답도 본문 스키마를 선언하지 않는다")
    void generatedSpec_401NeverDeclaresABody() throws Exception {
        // 401 은 우리 코드가 만들지 않는다 — Spring Security 의 HttpStatusEntryPoint 가
        // 본문 없이 상태 코드만 돌려준다(SecurityConfig 의 exceptionHandling). 손으로 쓴 계약
        // (openapi.yaml 의 components/responses/Unauthorized)도 #5 에서 본문 없음으로 확정했다.
        //
        // 그런데 컨트롤러의 @ApiResponse 애너테이션은 그 사실을 모른다. MediaController 4곳이
        // 401 에 JSON ErrorResponse 본문을 선언하고 있었고, 그래서 손으로 쓴 계약과 생성된
        // 계약이 서로 다른 말을 했다. 클라이언트가 생성된 쪽을 믿으면 오지 않는 본문을 파싱한다.
        List<String> withBody = new ArrayList<>();

        forEachOperation(generatedSpec().path("paths"), (label, operation) -> {
            JsonNode content = operation.path("responses").path("401").path("content");
            if (!content.isMissingNode() && content.size() > 0) {
                withBody.add(label + " → " + content.fieldNames().next());
            }
        });

        assertThat(withBody)
                .as("401 은 본문 없이 나간다. 계약이 본문을 약속하면 클라이언트가 없는 것을 기다린다")
                .isEmpty();
    }


    // ─────────── 반대 방향: 계약이 약속한 것에 핸들러가 있는가 ───────────

    /**
     * HTTP 메서드가 아닌 경로 수준 키. {@code paths./x.parameters} 는 오퍼레이션이 아니다.
     */
    private static final Set<String> HTTP_METHODS =
            Set.of("get", "post", "put", "patch", "delete", "head", "options", "trace");

    @Test
    @DisplayName("정본이 약속한 모든 오퍼레이션은 핸들러가 있거나, 없다고 스스로 표시한다")
    void contract_everyOperationEitherHasAHandlerOrSaysSo() throws Exception {
        Set<String> generated = operationsOf(generatedSpec());
        List<String> unmarked = new ArrayList<>();

        for (Map.Entry<String, Map<String, Object>> op : handWrittenOperations().entrySet()) {
            if (generated.contains(op.getKey())) {
                continue;
            }
            Object status = op.getValue().get("x-status");
            if (!"planned".equals(status) && !"framework".equals(status)) {
                unmarked.add(op.getKey());
            }
        }

        assertThat(unmarked)
                .as("""
                        이 문서는 "서버가 무엇을 약속하는가" 의 단일 출처다(#4). 핸들러 없는 경로를 \
                        표시 없이 실어 두면 그것을 보고 만든 앱이 404 를 받는다 — 실제로 열여섯 개가 \
                        그랬다(#201). 구현이 아직이면 x-status: planned 를, 우리 컨트롤러가 아니면 \
                        x-status: framework 를 적고 x-status-note 에 무엇이 막고 있는지 한 줄 남긴다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("핸들러가 붙은 오퍼레이션에는 planned 표시가 남아 있지 않다")
    void contract_plannedIsRemovedOnceTheHandlerLands() throws Exception {
        Set<String> generated = operationsOf(generatedSpec());
        List<String> stale = new ArrayList<>();

        for (Map.Entry<String, Map<String, Object>> op : handWrittenOperations().entrySet()) {
            if (generated.contains(op.getKey()) && "planned".equals(op.getValue().get("x-status"))) {
                stale.add(op.getKey());
            }
        }

        assertThat(stale)
                .as("""
                        표시는 한 방향으로만 썩는다 — 구현이 붙는 날 아무도 계약으로 돌아가지 않는다. \
                        그러면 "아직 없다" 고 적힌 경로를 앱이 안 쓰고 지나간다. 여기서 잡는다.""")
                .isEmpty();
    }

    /** 손으로 쓴 정본의 오퍼레이션 → 그 오퍼레이션 맵. 키는 {@code "GET /api/dogs/{}"} 꼴이다. */
    @SuppressWarnings("unchecked")
    private static java.util.Map<String, Map<String, Object>> handWrittenOperations() throws Exception {
        String raw = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);
        Map<String, Object> spec = (Map<String, Object>) new Yaml().load(raw);
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");

        assertThat(paths)
                .as("정본에서 paths 를 못 읽으면 아래 단언들이 조용히 통과한다")
                .isNotNull();

        java.util.Map<String, Map<String, Object>> out = new java.util.LinkedHashMap<>();
        for (Map.Entry<String, Object> path : paths.entrySet()) {
            Map<String, Object> item = (Map<String, Object>) path.getValue();
            for (Map.Entry<String, Object> op : item.entrySet()) {
                if (!HTTP_METHODS.contains(op.getKey())) {
                    continue;
                }
                out.put(key(op.getKey(), path.getKey()), (Map<String, Object>) op.getValue());
            }
        }
        assertThat(out.size()).as("정본 오퍼레이션이 이렇게 적을 리 없다").isGreaterThan(30);
        return out;
    }

    /** 생성본의 오퍼레이션 집합. */
    private static Set<String> operationsOf(JsonNode spec) {
        Set<String> out = new LinkedHashSet<>();
        forEachOperation(spec.path("paths"), (label, ignored) -> {
            String[] parts = label.split(" ", 2);
            out.add(key(parts[0], parts[1]));
        });
        return out;
    }

    /**
     * 경로 변수의 <b>이름</b>은 계약과 코드가 다를 수 있다({@code {dogId}} vs {@code {id}}).
     * 그건 드리프트가 아니므로 이름을 지우고 자리만 비교한다.
     */
    private static String key(String method, String path) {
        return method.toUpperCase() + " " + path.replaceAll("\\{[^}]*\\}", "{}");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * 살아 있는 컨텍스트에서 실제로 생성되는 문서를 받는다.
     *
     * <p>{@code /v3/api-docs} 는 {@code app.security.docs-public=false}(기본값) 아래에서
     * {@code anyRequest().authenticated()} 로 떨어지므로 유효한 토큰이 필요하다.
     */
    private JsonNode generatedSpec() throws Exception {
        User reader = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("api-docs-reader@example.com")
                .name("보리")
                .build());
        String token = jwtProvider.createAccessToken(reader.getId(), reader.getRole());

        var response = mockMvc.perform(get("/v3/api-docs").header("Authorization", "Bearer " + token))
                .andReturn().getResponse();

        assertThat(response.getStatus())
                .as("생성된 계약을 받지 못하면 아래 단언들이 조용히 통과한다")
                .isEqualTo(200);
        return MAPPER.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }

    private static void forEachOperation(JsonNode paths, java.util.function.BiConsumer<String, JsonNode> visitor) {
        assertThat(paths.size())
                .as("생성된 계약에 경로가 하나도 없으면 이 테스트는 아무것도 지키지 못한다")
                .isGreaterThan(20);

        for (Map.Entry<String, JsonNode> path : paths.properties()) {
            for (Map.Entry<String, JsonNode> operation : path.getValue().properties()) {
                visitor.accept(operation.getKey().toUpperCase() + " " + path.getKey(), operation.getValue());
            }
        }
    }
}
