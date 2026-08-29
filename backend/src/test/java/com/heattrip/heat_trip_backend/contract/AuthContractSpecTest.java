package com.heattrip.heat_trip_backend.contract;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 계약 문서 자체를 검증한다 — 이슈 #23.
 *
 * 왜 테스트인가: `docs/04-api/openapi.yaml` 은 "계약이 코드보다 우선"(#4)이라고 선언한 문서인데,
 * 응답 스키마에 `required` 가 하나도 없어서 `{}` 빈 객체가 유효한 `AuthTokens` 이고 유효한 `User` 였다.
 * 즉 검증 기능이 꺼져 있었다. 사람이 리뷰로만 막으면 같은 상태로 되돌아간다.
 *
 * 네트워크를 타지 않는다. 저장소 안의 파일만 읽는다.
 */
class AuthContractSpecTest {

    private static Map<String, Object> spec;
    private static String openApiRaw;
    private static String apiSpecRaw;

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() throws IOException {
        Path apiDir = locateApiDocsDir();
        openApiRaw = Files.readString(apiDir.resolve("openapi.yaml"), StandardCharsets.UTF_8);
        apiSpecRaw = Files.readString(apiDir.resolve("api-spec.md"), StandardCharsets.UTF_8);
        spec = (Map<String, Object>) new Yaml().load(openApiRaw);
    }

    /** 테스트 작업 디렉터리(backend/)에서 위로 올라가며 docs/04-api 를 찾는다. */
    private static Path locateApiDocsDir() {
        Path cursor = Paths.get("").toAbsolutePath();
        while (cursor != null) {
            Path candidate = cursor.resolve("docs").resolve("04-api");
            if (Files.exists(candidate.resolve("openapi.yaml"))) {
                return candidate;
            }
            cursor = cursor.getParent();
        }
        throw new IllegalStateException("docs/04-api/openapi.yaml 을 찾지 못했다. 작업 디렉터리: "
                + Paths.get("").toAbsolutePath());
    }

    // ─────────────────────────── A. required — 구조적 뿌리 ───────────────────────────

    @Test
    @DisplayName("AuthTokens·User·Page 는 required 를 선언해 빈 객체 {} 가 유효한 응답으로 통과하지 않는다")
    void responseSchemas_declareRequiredSoEmptyObjectIsInvalid() {
        assertRequiredIsEnforced("AuthTokens", "accessToken", "expiresIn");
        assertRequiredIsEnforced("User", "id");
        assertRequiredIsEnforced("Page", "items", "hasMore");
    }

    private void assertRequiredIsEnforced(String schemaName, String... mustRequire) {
        Map<String, Object> schema = schema(schemaName);
        List<String> required = stringList(schema.get("required"));

        // required 가 비어 있으면 JSON Schema 상 `{}` 가 유효하다. 그 상태를 막는 것이 이 단언의 목적이다.
        assertThat(required)
                .as("%s 에 required 가 없으면 {} 가 유효한 응답이 된다", schemaName)
                .isNotEmpty()
                .contains(mustRequire);

        Map<String, Object> properties = asMap(schema.get("properties"));
        assertThat(properties.keySet())
                .as("%s 의 required 항목은 properties 에도 선언돼 있어야 한다", schemaName)
                .containsAll(required);

        // 선언만 보지 말고 실제로 평가한다: 빈 객체는 걸리고, 필수 필드를 채운 객체는 통과해야 한다.
        assertThat(missingRequiredKeys(required, Map.of()))
                .as("빈 객체 {} 가 유효한 %s 로 통과하면 안 된다", schemaName)
                .containsExactlyInAnyOrderElementsOf(required);
        assertThat(missingRequiredKeys(required, filledWith(required)))
                .as("필수 필드를 모두 채운 객체는 %s 로 통과해야 한다", schemaName)
                .isEmpty();
    }

    /** JSON Schema 의 `required` 키워드를 그대로 평가한다(빠진 키 목록을 돌려준다). */
    private static List<String> missingRequiredKeys(List<String> required, Map<String, Object> candidate) {
        return required.stream().filter(key -> !candidate.containsKey(key)).toList();
    }

    private static Map<String, Object> filledWith(List<String> keys) {
        return keys.stream().collect(java.util.stream.Collectors.toMap(key -> key, key -> "값"));
    }

    // ─────────────────────────── B. subject 규약 ───────────────────────────

    @Test
    @DisplayName("두 계약 문서 어디에도 subject 가 사용자 email 이라는 서술이 남아 있지 않다")
    void spec_doesNotClaimSubjectIsEmail() {
        assertThat(openApiRaw)
                .as("소셜 로그인 경로의 sub 는 email 이 아니다. 계약이 거짓 불변식을 선언하면 안 된다")
                .doesNotContain("subject = 사용자 email");
        assertThat(apiSpecRaw)
                .as("openapi.yaml 만 고치면 api-spec.md 에 같은 거짓 서술이 남는다")
                .doesNotContain("subject = 사용자 email");
        assertThat(openApiRaw).contains("불투명 사용자 키");
        assertThat(apiSpecRaw).contains("불투명 사용자 키");
    }

    @Test
    @DisplayName("계약이 '소셜 토큰으로는 /auth/me 계열이 아직 400 이다'라는 알려진 결함을 #5 와 함께 적어 둔다")
    void spec_recordsKnownAuthMeDefectAndItsOwner() {
        // 왜 테스트인가: 이 결함은 코드가 아니라 '기록'으로만 존재한다. 이슈 #7 은 저장 구조만
        // 고치고 조회 경로(AuthController.me → findByEmail)를 일부러 남겼다 — 그건 #5 의 범위다.
        // 기록이 사라지면 #7 이 완료 조건 2("이메일 없는 카카오 계정으로 GET /auth/me 가 200")를
        // 만족한 것처럼 보인 채 닫힌다. 실제로는 지금 모든 소셜 계정에서 400 이다.
        // #5 가 들어와 결함이 사라지면 이 테스트가 빨간불이 되고, 그때 이 문단을 지우면 된다.
        String description = String.valueOf(asMap(spec.get("info")).get("description"));

        assertThat(description)
                .as("알려진 결함이라는 사실과 영향 범위가 계약에 적혀 있다")
                .contains("알려진 결함", "/auth/me", "400");
        assertThat(description)
                .as("누가 고치는지(#5)가 함께 적혀 있지 않으면 기록이 미아가 된다")
                .contains("#5");
    }

    @Test
    @DisplayName("bearerAuth 는 실제 발급 클레임(sub·role·iat·exp)을 description 으로 밝힌다")
    void bearerAuth_documentsActualClaims() {
        Map<String, Object> bearerAuth =
                asMap(asMap(asMap(spec.get("components")).get("securitySchemes")).get("bearerAuth"));
        String description = String.valueOf(bearerAuth.get("description"));

        assertThat(description).contains("`sub`", "`role`", "`iat`", "`exp`");
        assertThat(description)
                .as("아직 없는 클레임(jti)을 있는 것처럼 적으면 안 된다")
                .contains("`jti`");
    }

    // ─────────────────────────── C. 실재하는 경로의 등재 ───────────────────────────

    @Test
    @DisplayName("구현되어 동작 중인 인증 경로가 계약에 전부 등재돼 있다")
    void implementedAuthEndpoints_areAllDocumented() {
        Map<String, Object> paths = asMap(spec.get("paths"));

        assertThat(paths).containsKeys(
                "/auth/signup",
                "/auth/login",
                "/auth/me",
                "/oauth2/authorization/{provider}");
        assertThat(asMap(paths.get("/auth/signup"))).containsKey("post");
        assertThat(asMap(paths.get("/auth/login"))).containsKey("post");
        assertThat(asMap(paths.get("/auth/me")))
                .as("PUT /auth/me 는 구현·앱 호출 모두 존재하는데 계약에서 빠져 있었다")
                .containsKeys("get", "put", "delete");
    }

    @Test
    @DisplayName("구현이 없는 계약 경로는 description 에 미구현임이 명시돼 있다")
    void unimplementedOperations_areMarkedAsSuch() {
        record Op(String path, String method) {}
        List<Op> unimplemented = List.of(
                new Op("/auth/oauth/{provider}", "get"),
                new Op("/auth/oauth/{provider}/callback", "post"),
                new Op("/auth/token/refresh", "post"),
                new Op("/auth/logout", "post"));

        Map<String, Object> paths = asMap(spec.get("paths"));
        for (Op op : unimplemented) {
            Map<String, Object> operation = asMap(asMap(paths.get(op.path())).get(op.method()));
            assertThat(String.valueOf(operation.get("description")))
                    .as("%s %s 는 백엔드 핸들러가 없다. 계약이 그 사실을 말해야 한다", op.method(), op.path())
                    .contains("미구현");
            assertThat(operation)
                    .as("%s %s 에 기계가 읽을 미구현 표식이 필요하다", op.method(), op.path())
                    .containsEntry("x-implementation-status", "not-implemented");
        }
    }

    // ─────────────────────────── D. 스키마 정합 ───────────────────────────

    @Test
    @DisplayName("User 는 email 을 가지고 provider enum 에 local 이 있으며 nickname 이 null 을 허용한다")
    void userSchema_matchesActualResponse() {
        Map<String, Object> properties = asMap(schema("User").get("properties"));

        assertThat(properties)
                .as("subject 서술과의 자기모순 해소 — 계약상 클라이언트가 자기 email 을 알 수 있어야 한다")
                .containsKeys("email", "name", "nickname", "gender", "age",
                        "travelType", "imageUrl", "createdAt", "updatedAt");

        assertThat(stringList(asMap(properties.get("provider")).get("enum")))
                .as("이메일/비밀번호 가입 사용자를 표현할 값이 없었다")
                .contains("local");

        assertThat(stringList(asMap(properties.get("nickname")).get("type")))
                .as("소셜 가입 경로에서 nickname 은 설정되지 않아 null 이 내려온다")
                .contains("null");
    }

    @Test
    @DisplayName("isNew 는 영속 프로필(User)이 아니라 로그인 응답(AuthTokens)에 있다")
    void isNew_livesOnAuthTokensNotUser() {
        assertThat(asMap(schema("AuthTokens").get("properties")))
                .as("isNew 는 로그인 1회성 이벤트 속성이다")
                .containsKey("isNew");
        assertThat(asMap(schema("User").get("properties")))
                .as("GET /auth/me 응답에 의미 없는 isNew 가 남아 있으면 안 된다")
                .doesNotContainKey("isNew");
    }

    // ─────────────────────────── E. 보안·응답 정합 ───────────────────────────

    @Test
    @DisplayName("/auth/logout 은 401 응답과 전 기기 로그아웃 범위를 명시한다")
    void logout_declares401AndScope() {
        Map<String, Object> logout = asMap(asMap(asMap(spec.get("paths")).get("/auth/logout")).get("post"));

        assertThat(asMap(logout.get("responses")))
                .as("인증을 요구하면서 401 을 선언하지 않은 유일한 오퍼레이션이었다")
                .containsKeys("204", "401");
        assertThat(String.valueOf(logout.get("summary")) + String.valueOf(logout.get("description")))
                .as("현재 기기만인지 전 기기인지가 어디에도 없었다")
                .contains("전 기기");
    }

    @Test
    @DisplayName("Auth 태그 설명이 실제 지원 공급자(카카오·구글)와 인가 경계를 말한다")
    void authTag_describesProvidersAndAuthorizationBoundary() {
        String authTagDescription = tagDescription("Auth");

        assertThat(authTagDescription).contains("카카오", "구글");
        assertThat(authTagDescription)
                .as("SecurityConfig 가 지켜야 할 인가 경계를 계약이 말해야 한다")
                .contains("/auth/logout", "bearerAuth");
    }

    // ─────────────────────────── F. 두 문서의 정합 ───────────────────────────

    @Test
    @DisplayName("두 계약 문서 모두 첫머리에 openapi.yaml 이 단일 출처임을 선언한다")
    void bothDocuments_declareOpenApiAsSingleSourceOfTruth() {
        assertThat(head(openApiRaw, 40)).contains("단일 출처");
        assertThat(head(apiSpecRaw, 20))
                .as("두 문서가 충돌할 때 어느 쪽이 기준인지가 어디에도 없었다")
                .contains("단일 출처", "openapi.yaml");
    }

    @Test
    @DisplayName("api-spec.md 의 딥링크 스킴이 코드와 같은 heattrip 이다")
    void apiSpec_usesTheDeepLinkSchemeTheCodeActuallyUses() {
        assertThat(apiSpecRaw)
                .as("이 문서를 보고 구현하면 콜백을 못 받는 상태였다")
                .doesNotContain("pawloop://");
        assertThat(apiSpecRaw).contains("heattrip://login-callback");
    }

    // ─────────────────────────── helpers ───────────────────────────

    private static String head(String text, int lines) {
        String[] split = text.split("\\R");
        return String.join("\n", List.of(split).subList(0, Math.min(lines, split.length)));
    }

    private static Map<String, Object> schema(String name) {
        return asMap(asMap(asMap(spec.get("components")).get("schemas")).get(name));
    }

    private static String tagDescription(String tagName) {
        for (Object tag : (List<?>) spec.get("tags")) {
            Map<String, Object> entry = asMap(tag);
            if (tagName.equals(entry.get("name"))) {
                return String.valueOf(entry.get("description"));
            }
        }
        throw new AssertionError(tagName + " 태그가 계약에 없다");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object node) {
        assertThat(node).isInstanceOf(Map.class);
        return (Map<String, Object>) node;
    }

    private static List<String> stringList(Object node) {
        if (node == null) {
            return List.of();
        }
        assertThat(node).isInstanceOf(List.class);
        return ((List<?>) node).stream().map(String::valueOf).toList();
    }
}
