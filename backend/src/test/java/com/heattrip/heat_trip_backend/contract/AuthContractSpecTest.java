package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.chat.ChatErrorCode;

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

    // unimplementedOperations_areMarkedAsSuch 는 여기 있었다. 마지막 항목이었던
    // POST /auth/oauth/{provider}/callback 이 #14 에서 구현되면서 목록이 비었고, 빈 목록을
    // 도는 반복문은 아무것도 지키지 못한다 — 그 테스트의 주석이 "마지막 항목이 구현될 때는
    // 이 테스트를 지워라, 비워 두지 마라" 고 적어 둔 대로 지웠다. 자리를 이어받는 것은
    // 아래 oauthCallbackOperation_isNoLongerMarkedUnimplemented 다.
    //
    // 계약에 미구현 경로가 다시 생기면 이 테스트를 되살려라 — 목록이 비어 있지 않을 때만
    // 의미가 있다.

    @Test
    @DisplayName("POST /auth/oauth/{provider}/callback 은 더 이상 미구현이 아니며 1회용 코드 교환임을 계약이 말한다")
    void oauthCallbackOperation_isNoLongerMarkedUnimplemented() {
        Map<String, Object> callback = asMap(asMap(asMap(spec.get("paths"))
                .get("/auth/oauth/{provider}/callback")).get("post"));

        assertThat(callback)
                .as("기계가 읽는 미구현 표식이 남으면 클라이언트 생성기가 이 경로를 건너뛴다")
                .doesNotContainKey("x-implementation-status");

        String description = String.valueOf(callback.get("description"));
        assertThat(description)
                .as("'미구현' 은 이력 서술로만 남아야 한다 — 현재형으로 남으면 클라이언트가 이 경로를 피한다")
                .contains("2026-08 이전 이 절은");
        assertThat(description)
                .as("이 경로가 소셜 토큰의 유일한 통로라는 사실을 모르면 앱이 딥링크에서 토큰을 계속 찾는다")
                .contains("1회용");
        assertThat(description)
                .as("재사용·만료가 401 이라는 것을 모르면 앱은 그것을 서버 버그로 신고한다")
                .contains("401");

        assertThat(asMap(callback.get("responses")).keySet())
                .as("한도에 걸리면 429 다 — 계약에 없으면 앱이 '서버 고장' 으로 읽고 재시도 루프를 돈다")
                .contains("200", "401", "429");
    }

    @Test
    @DisplayName("GET /auth/oauth/{provider} 는 더 이상 미구현이 아니며 302 래퍼임과 400 을 계약이 말한다")
    void startOAuthOperation_isNoLongerMarkedUnimplemented() {
        // 이 경로의 계약은 "미구현 — 핸들러가 없습니다" 라고 적었는데 핸들러는 있었고 빈 200 을
        // 줬다. 계약도 코드도 거짓이었고 unimplementedOperations_areMarkedAsSuch 가 그 거짓이
        // **남아 있기를** 요구해 초록불로 고정하고 있었다. 자리를 이쪽으로 옮긴다. (#10)
        Map<String, Object> startOAuth =
                asMap(asMap(asMap(spec.get("paths")).get("/auth/oauth/{provider}")).get("get"));

        assertThat(startOAuth)
                .as("기계가 읽는 미구현 표식이 남으면 클라이언트 생성기가 이 경로를 건너뛴다")
                .doesNotContainKey("x-implementation-status");

        String description = String.valueOf(startOAuth.get("description"));
        assertThat(description).doesNotContain("미구현");
        assertThat(description)
                .as("인증 로직을 재구현하지 않는다는 것이 이 경로의 전부다 — 그게 사라지면 사본이 생긴다")
                .contains("/oauth2/authorization/{provider}");
        assertThat(description)
                .as("빈 200 을 주던 시절의 기록을 지우면 같은 거짓이 되살아난다")
                .contains("빈 200");

        assertThat(asMap(startOAuth.get("responses")).keySet())
                .as("화이트리스트 밖 공급자는 302 가 아니라 400 이다 (완료 조건 5·11)")
                .contains("302", "400");

        // #14 는 "돌아온 state 가 다르면 로그인 실패로 처리하라" 를 계약 본문에 못 박았다.
        // 이 호환 경로가 state 를 선언하지 않으면, 계약만 보고 구현한 클라이언트는 state 를
        // 실을 자리를 못 찾거나 실어도 버려진다 — 그러면 로그인이 100% 실패한다.
        @SuppressWarnings("unchecked")
        List<Object> parameters = (List<Object>) startOAuth.get("parameters");
        assertThat(parameters)
                .as("파라미터 목록 자체가 없다")
                .isNotNull();
        assertThat(parameters.stream()
                .map(AuthContractSpecTest::asMap)
                .map(param -> String.valueOf(param.get("name")))
                .toList())
                .as("state 를 옮긴다는 사실이 계약에 없으면 그 경로로 시작한 클라이언트가 조용히 실패한다")
                .contains("state");
    }

    @Test
    @DisplayName("로그인·회원가입 계약이 '목표' 가 아니라 구현된 사실을 말하고 앱이 깨지는 지점을 경고한다")
    void loginAndSignup_declareTheShippedShapeAndItsBreakingChange() {
        Map<String, Object> paths = asMap(spec.get("paths"));
        String login = String.valueOf(asMap(asMap(paths.get("/auth/login")).get("post")).get("description"));
        String signup = String.valueOf(asMap(asMap(paths.get("/auth/signup")).get("post")).get("description"));

        // "목표 계약입니다" 는 '아직 구현이 다르다' 는 뜻이다. #10 이 구현을 맞췄으므로 거짓이다.
        assertThat(login).doesNotContain("목표 계약입니다");
        assertThat(signup).doesNotContain("목표 계약입니다");

        // 앱은 이 두 응답을 평문으로 파싱하고 있었다(#11·#12 소유). 무엇이 어떻게 바뀌었는지가
        // 계약에 없으면 앱 레인은 자기가 왜 깨졌는지 알 방법이 없다.
        assertThat(login)
                .as("response.body 를 그대로 토큰으로 저장하던 코드가 조용히 깨진다")
                .contains("JWT 원문 문자열");
        assertThat(signup)
                .as("200 만 성공으로 보던 코드가 201 을 실패로 읽는다")
                .contains("회원가입 성공");

        // 2026-09 이전에는 여기가 **201 + User** 였고, 같은 이메일이면 409 였다. #635 가 가입을
        // 둘로 쪼갰다 — 이 경로는 코드를 메일로 보내기만 하고(202), 계정은 verify 에서 생긴다.
        //
        //   * 만들어진 것이 없는데 201 을 주면 **거짓말**이다. 앱이 응답에서 id 를 읽으려 든다
        //   * 409 는 그 자체가 "이 사람이 가입했나" 를 묻는 조회 수단이 된다 — 로그인이 401 에서
        //     이메일과 비밀번호를 구분하지 않는 것과 같은 이유다(#6)
        //
        // 그래서 여기는 202 와 400 **둘뿐**이다. contains 가 아니라 정확히 같은지를 재는 이유는,
        // 201·409 가 다시 끼어드는 날 이 검사가 조용히 통과하면 안 되기 때문이다.
        assertThat(asMap(asMap(asMap(paths.get("/auth/signup")).get("post")).get("responses")).keySet())
                .as("계정은 verify 에서 생긴다 — 여기서 201 을 주면 만들지도 않은 것을 만들었다고 말한다 (#635)")
                .containsExactlyInAnyOrder("202", "400");
        assertThat(signup)
                .as("201 을 기다리던 앱이 왜 202 를 받는지 계약에 없으면 앱 레인은 자기가 왜 깨졌는지 모른다")
                .contains("201");

        // 인증 경로가 없으면 위의 202 는 "가입이 사라졌다" 는 뜻이 된다. 계약에 끝까지 적혀
        // 있어야 계약만 보고 만든 클라이언트가 가입을 끝낼 수 있다.
        assertThat(asMap(asMap(asMap(paths.get("/auth/signup/verify")).get("post")).get("responses")).keySet())
                .as("401(코드가 틀렸다)과 410(다시 받아야 한다)을 뭉개면 앱이 '다시 보내기' 를 언제 권할지 모른다")
                .contains("200", "401", "410");
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
    @DisplayName("소셜 로그인 딥링크 서술이 1회용 코드·state 를 말하고 토큰이 실리지 않음을 못 박는다")
    void spec_documentsTheOneTimeCodeOnTheDeepLink() {
        // 이 서술이 옛 형태로 돌아가면 앱은 딥링크에서 오지 않는 토큰을 계속 찾는다.
        String description = String.valueOf(asMap(asMap(asMap(spec.get("paths"))
                .get("/oauth2/authorization/{provider}")).get("get")).get("description"));

        assertThat(description)
                .as("딥링크의 실제 모양이다 (#14 완료 조건 1)")
                .contains("?code=", "state=");
        assertThat(description)
                .as("'토큰이 없다' 를 계약이 말하지 않으면 클라이언트는 그것을 서버 버그로 읽는다")
                .contains("딥링크에는 토큰이 없습니다");
        assertThat(description)
                .as("state 불일치를 로그인 실패로 처리하는 것은 클라이언트의 몫이다 — 계약이 요구해야 한다")
                .contains("로그인 실패로");
        assertThat(description)
                .as("토큰을 URL 로 넘기던 시절의 기록을 지우면 같은 설계가 되살아난다")
                .contains("?token=<JWT>&refresh=<refreshToken>");
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
    @DisplayName("Error 봉투가 required 와 닫힌 code 어휘를 선언해 오류 본문이 한 형태로 고정된다")
    void errorSchema_declaresTheClosedCodeVocabulary() {
        // 예전에는 required 도 enum 도 없어서 `{}` 가 유효한 Error 였고, 같은 상태에 서로 다른
        // code 문자열을 적어도 계약이 아무 말을 하지 않았다(VALIDATION 과 VALIDATION_ERROR 가
        // 문서에 공존했다). 어휘를 계약이 소유한다. (#10)
        Map<String, Object> error = schema("Error");

        assertThat(stringList(error.get("required")))
                .as("required 가 없으면 빈 객체 {} 가 유효한 오류 응답이 된다")
                .containsExactly("error");

        Map<String, Object> body = asMap(asMap(error.get("properties")).get("error"));
        assertThat(stringList(body.get("required"))).contains("code", "message");
        assertThat(asMap(body.get("properties")))
                .as("traceId 가 없으면 사용자가 서버 로그에서 자기 요청을 지목할 방법이 없다")
                .containsKey("traceId");

        // 어휘의 출처는 둘이다. 하나는 상태→코드 표(GlobalExceptionHandler.codeOf)이고,
        // 다른 하나는 ChatErrorCode 다 — 그 넷만 상태에서 파생되지 않는다. ROOM_MEMBER_LIMIT
        // 과 INVITE_USES_EXHAUSTED 가 둘 다 409 인데 앱이 보여줄 화면이 다르기 때문이다(#74).
        //
        // 두 번째 목록을 여기 손으로 적지 않고 enum 에서 뽑는 이유: 적어 두면 코드를 하나
        // 더할 때 계약과 테스트를 함께 고쳐야 한다는 사실을 아무도 안 알려준다. 지금은
        // ChatErrorCode 에 값을 하나 더하는 순간 이 단언이 빨간불이고, 고치는 방법은
        // 계약에 그 코드를 등재하는 것뿐이다 (이슈 #75).
        List<String> expected = new ArrayList<>(List.of("VALIDATION", "FORBIDDEN", "NOT_FOUND",
                "METHOD_NOT_ALLOWED", "CONFLICT", "UNSUPPORTED_MEDIA_TYPE",
                "RATE_LIMITED", "INTERNAL"));
        for (ChatErrorCode chatCode : ChatErrorCode.values()) {
            expected.add(chatCode.name());
        }

        List<String> codes = stringList(asMap(asMap(body.get("properties")).get("code")).get("enum"));
        assertThat(codes)
                .as("계약의 code 어휘가 서버가 실제로 내보내는 집합과 갈라졌다 — "
                        + "GlobalExceptionHandler.codeOf 의 여덟 + ChatErrorCode 의 %d 개다",
                        ChatErrorCode.values().length)
                .containsExactlyInAnyOrderElementsOf(expected);
        assertThat(codes)
                .as("401 은 본문 자체가 없다 — 코드를 두면 앱이 오지 않는 본문을 기다린다 (#5)")
                .doesNotContain("UNAUTHORIZED");
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

        // **문장이 목록과 갈리는 것을 여기서 막는다.** 이 설명은 SecurityConfig 의 permitAll
        // 목록에 대한 정본인데, 사람이 손으로 적는 문장이라 경로가 늘 때 같이 안 늘어난다 —
        // #635 가 `/auth/signup/verify`·`/auth/signup/resend` 를 더했을 때 실제로 그랬다.
        // "뿐입니다" 라고 단정해 놓고 둘을 빠뜨리면, 그 문장을 읽고 구현하는 사람이 두 경로를
        // 인증 뒤로 넣는다 — 그러면 코드를 받은 사람이 토큰이 없어 가입을 못 끝낸다.
        assertThat(unauthenticatedAuthPaths())
                .as("계약이 security: [] 로 연 /auth 경로인데 인가 경계 문장에 이름이 없다")
                .allSatisfy(path -> assertThat(authTagDescription)
                        .as("%s (또는 그것을 덮는 와일드카드)", path)
                        .containsAnyOf(path, wildcardOf(path)));

        // 같은 문장이 api-spec.md 에도 있다. 두 문서가 **다른 목록**을 들면 어느 쪽을 보고
        // 구현했느냐로 결과가 갈린다 — 그건 계약이 없는 것과 같다.
        String mirrored = lineStartingWith(apiSpecRaw, "**인가 경계**");
        assertThat(unauthenticatedAuthPaths())
                .as("api-spec.md 의 인가 경계 줄이 계약과 다른 목록을 든다")
                .allSatisfy(path -> assertThat(mirrored)
                        .as("%s (또는 그것을 덮는 와일드카드)", path)
                        .containsAnyOf(path, wildcardOf(path)));
    }

    /** 그 말머리로 시작하는 줄 하나. 없으면 그 자리에서 선다 — 조용히 빈 문자열을 비교하면 안 된다. */
    private static String lineStartingWith(String document, String prefix) {
        String found = document.lines().filter(line -> line.startsWith(prefix)).findFirst().orElse(null);
        assertThat(found)
                .as("api-spec.md 에서 '%s' 로 시작하는 줄을 못 찾았다 — 문서 구조가 바뀌었다", prefix)
                .isNotNull();
        return found;
    }

    /**
     * {@code /auth/oauth/{provider}} 처럼 자리표시자가 있는 경로를 문장이 쓰는 모양으로.
     *
     * <p>문장은 {@code /auth/oauth/**} 라고 적는다 — 자리표시자 이름까지 본문에 옮겨 적게 하면
     * 파라미터 이름을 바꾸는 날 이 검사가 엉뚱한 곳에서 빨개진다.
     */
    private static String wildcardOf(String path) {
        int brace = path.indexOf('{');
        return brace < 0 ? path : path.substring(0, brace) + "**";
    }

    /** 계약이 {@code security: []} 로 연 {@code /auth/...} 경로 전부. */
    private static List<String> unauthenticatedAuthPaths() {
        List<String> open = new ArrayList<>();
        asMap(spec.get("paths")).forEach((path, node) -> {
            if (!path.startsWith("/auth/")) {
                return;
            }
            boolean anyOpen = asMap(node).values().stream()
                    .filter(Map.class::isInstance)
                    .map(AuthContractSpecTest::asMap)
                    .anyMatch(operation -> operation.get("security") instanceof List<?> security
                            && security.isEmpty());
            if (anyOpen) {
                open.add(path);
            }
        });
        assertThat(open)
                .as("security: [] 인 /auth 경로를 하나도 못 찾았다 — 파서가 늙었거나 계약이 통째로 바뀌었다")
                .isNotEmpty();
        return open;
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
