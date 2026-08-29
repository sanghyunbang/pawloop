package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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

    // spec_recordsKnownAuthMeDefectAndItsOwner 는 #5 와 함께 삭제됐다.
    //
    // 그 테스트는 "소셜 토큰으로는 /auth/me 가 400" 이라는 **알려진 결함의 기록**이 계약에
    // 남아 있기를 요구했다. #5 가 결함 자체를 없앴으므로 계약의 그 문단이 거짓이 되었고,
    // 문단을 지우자 이 테스트가 빨간불이 되었다(그렇게 설계돼 있었다) — 확인한 뒤 함께 지운다.
    // 지금 그 자리를 지키는 것은 AuthMeIntegrationTest 다: 소셜 계정 토큰으로 실제 200 이 나오는지
    // 매번 확인한다. 기록이 아니라 행동으로 잠긴 상태다.

    /** 계약 검증용 HS256 키. 정확히 32바이트 — 값 자체에는 의미가 없다. */
    private static final String CONTRACT_TEST_SECRET = "test-only-secret-key-32bytes-min!!";

    @Test
    @DisplayName("bearerAuth 의 클레임 표가 실제로 발급되는 토큰의 클레임 집합과 정확히 일치한다")
    void bearerAuth_documentsActualClaims() {
        // 예전 이 테스트의 단언은 contains("`jti`") 하나뿐이었다. 그래서 문서가 "jti 가 없다"고
        // 적어도 "jti 가 있다"고 적어도 똑같이 통과했다 — 잠그려던 것(거짓 서술 방지)을 전혀
        // 잠그지 못하는 형태였다. 문자열 포함 검사를 걷어내고 실제 토큰과 대조한다. (#5 코멘트 → #9)
        String description = bearerAuthDescription();

        Claims actual = issueRealAccessToken();

        assertThat(documentedPresentClaims(description))
                .as("문서의 클레임 표와 발급 토큰의 클레임 키 집합이 어긋나면 계약이 거짓이다")
                .containsExactlyInAnyOrderElementsOf(actual.keySet());

        // 문서가 "아직 없다"고 적은 클레임은 토큰에도 실제로 없어야 한다. 누군가 코드에
        // .setId(UUID) 를 넣으면 문서를 고치기 전까지 여기서 빨간불이 난다.
        for (String absent : documentedAbsentClaims(description)) {
            assertThat(actual.keySet())
                    .as("문서가 '아직 없는 클레임' 이라고 적은 %s 가 토큰에 실제로 들어 있다", absent)
                    .doesNotContain(absent);
        }
    }

    @Test
    @DisplayName("jti 를 도입하지 않기로 한 판단과 그 소유자가 계약에 적혀 있다")
    void bearerAuth_recordsWhyJtiIsAbsent() {
        // 이 문장이 사라지면 "왜 없는지" 를 아무도 모른 채 다시 논의가 시작된다.
        // 예전에는 "도입은 이슈 #9" 라고 적혀 있었는데, #9 가 jti 없이 닫혔으므로 그 문장은
        // 거짓이 되었다. 사실에 맞게 고치는 것까지가 #9 의 일이다.
        String description = bearerAuthDescription();

        assertThat(description).contains("`jti`", "`prv`");
        assertThat(description)
                .as("소비자(블록리스트 저장소) 없이 형식만 먼저 박지 않는다는 것이 판단의 근거다")
                .contains("블록리스트");
        assertThat(apiSpecRaw)
                .as("openapi.yaml 만 고치면 api-spec.md 에 옛 소유자 지목이 남는다")
                .doesNotContain("`jti` 가 없어 로그아웃해도 액세스 토큰은 만료까지 유효하다(#9).");
    }

    private static String bearerAuthDescription() {
        Map<String, Object> bearerAuth =
                asMap(asMap(asMap(spec.get("components")).get("securitySchemes")).get("bearerAuth"));
        return String.valueOf(bearerAuth.get("description"));
    }

    /** 클레임 표의 각 행 첫 칸(백틱으로 감싼 이름)을 뽑는다. */
    private static List<String> documentedPresentClaims(String description) {
        List<String> claims = new ArrayList<>();
        Matcher matcher = Pattern.compile("(?m)^\\s*\\|\\s*`([a-zA-Z]+)`\\s*\\|").matcher(description);
        while (matcher.find()) {
            claims.add(matcher.group(1));
        }
        assertThat(claims).as("클레임 표를 하나도 못 읽었다면 이 테스트는 아무것도 지키지 못한다").isNotEmpty();
        return claims;
    }

    /** "아직 **없는** 클레임:" 문단에 적힌 이름들. 그 문단은 첫 빈 줄에서 끝난다. */
    private static List<String> documentedAbsentClaims(String description) {
        int start = description.indexOf("아직 **없는** 클레임:");
        assertThat(start).as("없는 클레임을 밝히는 문단이 사라졌다").isNotNegative();
        int end = description.indexOf("\n\n", start);
        String paragraph = (end < 0) ? description.substring(start) : description.substring(start, end);

        List<String> claims = new ArrayList<>();
        Matcher matcher = Pattern.compile("`([a-zA-Z]+)`").matcher(paragraph);
        while (matcher.find()) {
            claims.add(matcher.group(1));
        }
        assertThat(claims).isNotEmpty();
        return claims;
    }

    /**
     * 프로덕션 발급기로 토큰을 하나 만들어 파싱한다.
     *
     * <p>클레임 목록을 테스트에 다시 적지 않는 이유: 그러면 코드가 아니라 테스트의 사본과
     * 문서를 대조하게 되어, 코드가 바뀌어도 두 사본이 나란히 낡은 채 초록불이 된다.
     */
    private static Claims issueRealAccessToken() {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", CONTRACT_TEST_SECRET);
        ReflectionTestUtils.setField(provider, "expirationMillis", 3_600_000L);
        ReflectionTestUtils.invokeMethod(provider, "init");

        return Jwts.parserBuilder()
                .setSigningKey(Keys.hmacShaKeyFor(CONTRACT_TEST_SECRET.getBytes(StandardCharsets.UTF_8)))
                .build()
                .parseClaimsJws(provider.createAccessToken(42L, "ROLE_USER"))
                .getBody();
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

        // POST /auth/logout 은 AuthController.logout 으로 실재한다. 계약은 오래도록 그것을
        // "미구현 — 핸들러가 없습니다" 라고 적었고 아래 unimplementedOperations_areMarkedAsSuch 가
        // 그 거짓 서술이 **남아 있기를** 요구해 초록불로 고정하고 있었다. 자리를 이쪽으로 옮긴다. (#5)
        assertThat(asMap(paths.get("/auth/logout")))
                .as("핸들러가 있는 경로를 '핸들러가 없다'고 적는 계약은 앱을 잘못 인도한다")
                .containsKey("post");
        Map<String, Object> logout = asMap(asMap(paths.get("/auth/logout")).get("post"));
        assertThat(String.valueOf(logout.get("description")))
                .as("서버측 폐기가 없다는 사실은 남아야 한다 — 사라진 것은 '핸들러가 없다'는 거짓뿐이다")
                .doesNotContain("미구현")
                .contains("#9");
        assertThat(logout)
                .as("기계가 읽는 미구현 표식도 함께 걷어야 한다")
                .doesNotContainKey("x-implementation-status");
    }

    @Test
    @DisplayName("구현이 없는 계약 경로는 description 에 미구현임이 명시돼 있다")
    void unimplementedOperations_areMarkedAsSuch() {
        record Op(String path, String method) {}
        // /auth/token/refresh 는 #9 에서 구현되어 이 목록에서 빠졌다. 아래
        // refreshOperation_isNoLongerMarkedUnimplemented 가 그 자리를 지킨다.
        List<Op> unimplemented = List.of(
                new Op("/auth/oauth/{provider}", "get"),
                new Op("/auth/oauth/{provider}/callback", "post"));

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
    @DisplayName("/auth/logout 은 401 응답과 전 기기 로그아웃 범위를 summary·description 양쪽에 명시한다")
    void logout_declares401AndScope() {
        Map<String, Object> logout = asMap(asMap(asMap(spec.get("paths")).get("/auth/logout")).get("post"));

        assertThat(asMap(logout.get("responses")))
                .as("인증을 요구하면서 401 을 선언하지 않은 유일한 오퍼레이션이었다")
                .containsKeys("204", "401");

        // 예전에는 summary 와 description 을 **이어 붙인 문자열**에 대고 단언했다. 그래서 둘 중
        // 하나를 통째로 지워도 초록불이었다 — 잠근 척만 하는 형태다. 개별 필드로 조인다.
        assertThat(String.valueOf(logout.get("summary")))
                .as("목록에서 요약만 보는 사람에게도 범위가 보여야 한다")
                .contains("전 기기");
        assertThat(String.valueOf(logout.get("description")))
                .as("현재 기기만인지 전 기기인지가 어디에도 없었다")
                .contains("전 기기");
    }

    @Test
    @DisplayName("/auth/logout 설명이 '서버측 폐기가 실제로 일어난다' 와 '액세스 토큰은 만료까지 유효하다' 를 함께 말한다")
    void logout_declaresServerSideRevocationAndItsLimit() {
        // 두 문장이 함께 있어야 한다. 폐기가 일어난다는 사실만 적으면 앱이 로그아웃 직후 옛
        // 액세스 토큰이 통하는 것을 버그로 오해하고, 한계만 적으면 #9 이전의 거짓 서술로 돌아간다.
        String description = String.valueOf(
                asMap(asMap(asMap(spec.get("paths")).get("/auth/logout")).get("post")).get("description"));

        assertThat(description).contains("서버측 폐기가 실제로 일어납니다");
        assertThat(description)
                .as("알려진 한계는 거짓 서술이 아니다 — 지우면 안 된다")
                .contains("만료(≤1시간)까지 유효합니다");
    }

    @Test
    @DisplayName("/auth/token/refresh 는 더 이상 미구현이 아니며 회전·재사용 감지·직렬화 요구를 계약이 말한다")
    void refreshOperation_isNoLongerMarkedUnimplemented() {
        Map<String, Object> refresh =
                asMap(asMap(asMap(spec.get("paths")).get("/auth/token/refresh")).get("post"));

        assertThat(refresh)
                .as("기계가 읽는 미구현 표식이 남아 있으면 클라이언트 생성기가 이 경로를 건너뛴다")
                .doesNotContainKey("x-implementation-status");

        String description = String.valueOf(refresh.get("description"));
        assertThat(description).doesNotContain("미구현");
        assertThat(description)
                .as("회전한다는 사실을 모르면 앱이 옛 refresh 토큰을 계속 쓰다 전 기기가 끊긴다")
                .contains("회전");
        assertThat(description)
                .as("재사용 감지의 결과(전량 폐기)를 모르면 앱은 그것을 서버 버그로 신고한다")
                .contains("재사용 감지", "세션을 폐기");
        assertThat(description)
                .as("유예 창이 없으므로 동시 갱신 직렬화는 클라이언트의 책임이다 — 계약이 그걸 요구해야 한다")
                .contains("single-flight");
    }

    @Test
    @DisplayName("/auth/token/refresh 가 형식 오류의 실제 응답 코드(400·415)를 계약에 등재한다")
    void refreshOperation_declaresTheMalformedRequestStatuses() {
        // 이 경로는 비인증 공개 표면이다. 계약이 200·401 만 선언하고 있던 동안 실제로는
        // 깨진 JSON·잘못된 Content-Type·잘못된 메서드가 전부 500 으로 나갔다(#9 에서 실측).
        // 앱은 그걸 '서버 고장'으로 읽고 재시도 루프를 돈다.
        Map<String, Object> responses = asMap(asMap(asMap(asMap(spec.get("paths"))
                .get("/auth/token/refresh")).get("post")).get("responses"));

        assertThat(responses.keySet())
                .as("계약에 없는 상태 코드가 나가면 앱은 '재로그인하라' 와 '서버가 고장났다' 를 구분할 수 없다")
                .contains("200", "400", "401", "415");

        String description = String.valueOf(asMap(asMap(asMap(spec.get("paths"))
                .get("/auth/token/refresh")).get("post")).get("description"));
        assertThat(description)
                .as("400·415·405 를 401 처럼 다루면 앱이 멀쩡한 세션을 버리고 재로그인시킨다")
                .contains("400·415·405");
        assertThat(description)
                .as("파서 메시지를 본문에 실으면 요청 본문(= refresh 토큰 원문) 조각이 새어 나간다 (#6)")
                .contains("예외 메시지를 싣지 않습니다");
    }

    @Test
    @DisplayName("소셜 로그인 딥링크 서술에 refresh 파라미터와 그 파싱 주의가 적혀 있다")
    void spec_documentsTheRefreshTokenOnTheDeepLink() {
        // 액세스 토큰이 URL 의 꼬리가 아니게 되었다는 사실이 계약에 없으면, 'token=' 뒤를 전부
        // 잘라 쓰는 클라이언트가 조용히 손상된 토큰을 저장한다(모든 요청 401).
        String description = String.valueOf(asMap(asMap(asMap(spec.get("paths"))
                .get("/oauth2/authorization/{provider}")).get("get")).get("description"));

        assertThat(description).contains("&refresh=<refreshToken>");
        assertThat(description).contains("queryParameters['token']");
        assertThat(description)
                .as("자격증명 두 개가 URL 로 나가는 위험과 그 대체(#14)를 계약이 숨기면 안 된다")
                .contains("#14");
    }

    @Test
    @DisplayName("401 응답은 본문을 선언하지 않는다 — 서버가 실제로 본문 없는 401 만 돌려주기 때문이다")
    void unauthorizedResponse_declaresNoBody() {
        Map<String, Object> unauthorized =
                asMap(asMap(asMap(spec.get("components")).get("responses")).get("Unauthorized"));

        // 서버의 인증 실패는 두 경로뿐이고 둘 다 본문이 없다 —
        // SecurityConfig 의 HttpStatusEntryPoint(UNAUTHORIZED) 와
        // GlobalExceptionHandler.handleUnauthenticated 의 ResponseEntity<Void>.
        // 계약이 JSON Error 본문을 선언하면 앱이 error.code 로 분기하다 파싱에서 깨진다.
        assertThat(unauthorized)
                .as("28개 오퍼레이션이 이 응답을 $ref 한다 — 여기 한 줄이 앱 전체의 401 처리를 정한다")
                .doesNotContainKey("content");
        assertThat(String.valueOf(unauthorized.get("description")))
                .as("본문이 없다는 사실을 사람이 읽을 수 있게 적어야 한다")
                .contains("본문");
    }

    @Test
    @DisplayName("소셜 로그인 실패 딥링크의 error 코드 목록이 계약에 적혀 있다")
    void spec_documentsTheSocialLoginFailureDeepLinkCodes() {
        Map<String, Object> startOAuth = asMap(asMap(asMap(spec.get("paths"))
                .get("/oauth2/authorization/{provider}")).get("get"));
        String description = String.valueOf(startOAuth.get("description"));

        // 성공(`?token=`)만 적혀 있고 실패(`?error=`)는 코드 목록을 포함해 어디에도 없었다.
        // 앱은 모르는 코드를 받으면 조용히 무시하거나 빈 화면이 된다.
        assertThat(description).contains("?error=");
        assertThat(description)
                .as("서버가 실제로 보내는 코드다 — OAuth2SuccessHandler·OAuth2FailureHandler·CustomOAuth2UserService")
                .contains("email_already_registered", "account_state_invalid", "authentication_failed");
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
