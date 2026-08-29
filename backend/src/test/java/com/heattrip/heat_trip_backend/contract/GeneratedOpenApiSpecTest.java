package com.heattrip.heat_trip_backend.contract;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;

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
 * <p>실제로 그런 일이 있었다. {@link com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser} 는
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
class GeneratedOpenApiSpecTest {

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
