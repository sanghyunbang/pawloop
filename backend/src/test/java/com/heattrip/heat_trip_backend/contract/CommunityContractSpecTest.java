package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import com.heattrip.heat_trip_backend.community.controller.CommunityController;
import com.heattrip.heat_trip_backend.community.dto.CommentRequest;
import com.heattrip.heat_trip_backend.community.dto.CommentResponse;
import com.heattrip.heat_trip_backend.community.dto.PersonRefResponse;
import com.heattrip.heat_trip_backend.community.dto.PostRequest;
import com.heattrip.heat_trip_backend.community.dto.PostResponse;
import com.heattrip.heat_trip_backend.community.dto.ReactionSummaryResponse;
import com.heattrip.heat_trip_backend.community.service.CommunityService;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 커뮤니티 계약이 <b>도는 코드</b>·<b>api-spec.md</b>·<b>DB</b> 와 같은 것을 말하는지 본다 —
 * 이슈 #167.
 *
 * <h2>왜 필요한가</h2>
 * <p>#167 이 찾은 것은 {@code api-spec.md §6} 이 <b>계약에 없는 경로 열 군데</b>를 적고 그중
 * 다섯에 "✅ 구현" 을 붙여 둔 상태였다. {@code POST /api/posts/{postId}/reactions} 는 계약에도
 * 코드에도 없었고 응답 필드 이름도 {@code myReaction} 으로 달랐다. 그대로 짜면 404 다.
 *
 * <p>{@code openapi.yaml} 만 고치면 {@code api-spec.md} 에 같은 거짓 서술이 남는다 —
 * {@code AuthContractSpecTest:119} 가 적어 둔 문장이고, 그 장치가 {@code /auth} 에만 있었다.
 *
 * <h2>세 축을 본다</h2>
 * <ul>
 *   <li><b>코드 ↔ 계약</b> — 컨트롤러의 일곱 매핑, 응답 레코드의 필드.</li>
 *   <li><b>api-spec.md ↔ 계약</b> — §6 이 ✅ 라고 적은 경로는 계약에 <b>있어야</b> 하고,
 *       ⬜ 라고 적은 것은 <b>없어야</b> 한다. 뒤쪽이 없으면 계약이 앞서갈 때 문서만 낡는다.</li>
 *   <li><b>계약 ↔ 코드 ↔ DB</b> — {@code Board} 다섯 값과 {@code ReactionType} 셋.</li>
 * </ul>
 *
 * <h2>경로와 값을 손으로 적지 않는다</h2>
 * <p>경로는 컨트롤러 애너테이션에서, 응답 필드는 레코드 컴포넌트에서, 게시판 값은 서비스
 * 상수에서 읽는다. 손으로 적으면 <b>사본과 문서</b>를 대조하게 되어 둘이 나란히 낡은 채
 * 초록불이 된다({@code CareContractSpecTest} 가 같은 이유로 그렇게 한다).
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 문서를 읽고 클래스를 리플렉션으로 볼 뿐이다(#21).
 */
class CommunityContractSpecTest {

    private static Map<String, Object> spec;
    private static String apiSpecRaw;

    /** {@code api-spec.md} 의 커뮤니티 절. 여기 적힌 경로가 계약과 같아야 한다. */
    private static final String SECTION_HEADING = "## 6. 커뮤니티";

    /** {@code GET /api/community/posts?board=...} 꼴. 물음표 앞까지가 경로다. */
    private static final Pattern SPEC_ENDPOINT =
            Pattern.compile("(GET|POST|PATCH|PUT|DELETE)\\s+(/api/community/[^\\s`?]*)");

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() throws IOException {
        // 파일이 없으면 requireFile 이 여기서 던진다. skip 이 아니다 — 못 읽고 통과하면
        // 이 테스트는 아무것도 지키지 않으면서 초록불만 낸다.
        spec = (Map<String, Object>) new Yaml().load(readRepositoryFile("../docs/04-api/openapi.yaml"));
        apiSpecRaw = readRepositoryFile("../docs/04-api/api-spec.md");
    }

    // ─────────────────── A. 코드 ↔ 계약 ───────────────────

    @Test
    @DisplayName("컨트롤러의 일곱 매핑이 전부 계약에 등재돼 있다 — 경로 목록은 코드에서 읽는다")
    void everyImplementedEndpoint_isDeclaredInTheContract() {
        List<String> implemented = operationsOf(CommunityController.class);

        assertThat(implemented)
                .as("컨트롤러에서 매핑을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .hasSize(7);
        assertThat(declaredOperations())
                .as("""
                        계약에 없는 경로는 앱이 존재를 모른다 — design-first 라 앱은 이 파일을 보고 \
                        만든다. 경로 변수 이름까지 같아야 한다: 계약이 {postId} 인데 코드가 {id} 면 \
                        생성된 클라이언트의 시그니처가 틀린다.""")
                .containsAll(implemented);
    }

    @Test
    @DisplayName("Post·Comment·ReactionSummary·PersonRef 의 속성이 응답 레코드의 필드와 정확히 같다")
    void responseSchemas_matchTheResponseRecords() {
        assertThat(propertyNames("Post"))
                .as("""
                        계약과 응답 DTO 가 갈리면 앱이 없는 필드를 읽거나 있는 필드를 모른다. \
                        #167 이 찾은 §6 예시가 avatarUrl·placeName·bodyPreview·myReaction 을 \
                        적고 있었는데 넷 다 어디에도 없는 이름이었다.""")
                .containsExactlyInAnyOrderElementsOf(componentNames(PostResponse.class));

        assertThat(propertyNames("Comment"))
                .containsExactlyInAnyOrderElementsOf(componentNames(CommentResponse.class));

        assertThat(propertyNames("ReactionSummary"))
                .as("""
                        mine 은 required 가 아니지만 속성으로는 있어야 한다 — 게스트에게 null 로 \
                        나가는 것이 '비인증' 의 표현이다(ADR-0017 규약 6).""")
                .containsExactlyInAnyOrderElementsOf(componentNames(ReactionSummaryResponse.class));

        assertThat(propertyNames("PersonRef"))
                .as("""
                        이름만으로는 '나' 와 남을 가를 수 없다 — userId 가 함께 있어야 한다. \
                        2026-09 이전 Comment.author 에는 nickname 뿐이라 '내 댓글인가' 판별이 \
                        계약상 불가능했고, 앱은 문자열 '나' 를 표식으로 쓰고 있었다(ADR-0017 규약 5).""")
                .containsExactlyInAnyOrderElementsOf(componentNames(PersonRefResponse.class));
    }

    // ─────────────────── B. api-spec.md ↔ 계약 ───────────────────

    @Test
    @DisplayName("api-spec.md §6 이 구현됐다고 적은 경로가 전부 계약에 있다")
    void apiSpecSection_onlyClaimsPathsTheContractDeclares() {
        List<String> claimed = endpointsClaimedAsImplemented();

        assertThat(claimed)
                .as("§6 에서 ✅ 절의 경로를 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isNotEmpty();
        assertThat(declaredOperations())
                .as("""
                        openapi.yaml 만 고치면 api-spec.md 에 같은 거짓 서술이 남는다 \
                        (AuthContractSpecTest 가 /auth 에서 같은 이유로 두 파일을 함께 읽는다). \
                        #167 이 찾은 것이 정확히 그 상태였다 — §6 이 POST /api/posts/{postId}/reactions \
                        를 '✅ 구현(개편)' 으로 적었는데 계약에도 코드에도 없었다.""")
                .containsAll(claimed);
    }

    @Test
    @DisplayName("api-spec.md §6 이 계약에 없다고 적은 경로는 실제로 계약에 없다")
    void apiSpecSection_doesNotUnderstateWhatTheContractHas() {
        List<String> disclaimed = endpointsMarkedAbsent();

        assertThat(disclaimed)
                .as("⬜ 절의 경로를 하나도 못 읽었다 — 수정·삭제 넷이 아직 계약 밖이다(#211)")
                .isNotEmpty();
        assertThat(declaredOperations())
                .as("""
                        반대 방향도 잠근다. #211 이 수정·삭제를 계약에 넣는 날 이 단언이 빨간불이 \
                        되고, 그때 §6 의 ⬜ 를 함께 고치게 된다. 이게 없으면 계약이 앞서갈 때 \
                        문서만 조용히 낡는다.""")
                .doesNotContainAnyElementsOf(disclaimed);
    }

    // ─────────────────── C. 값의 출처 셋 ───────────────────

    @Test
    @DisplayName("Board 의 다섯 값이 계약·서비스 상수·DB CHECK 에서 같은 문자열이다")
    void boardHasOneSpelling() {
        Set<String> fromContract = Set.copyOf(enumOf("Board"));
        Set<String> fromCode = constantSet("BOARDS");

        assertThat(fromContract)
                .as("""
                        같은 값에 표기가 둘이면 어느 쪽이 정본인지 매번 물어야 한다. ADR-0016 이 \
                        board 를 ASCII 키로 정했고 한글은 앱이 드는 표시 문구가 됐다 — 그 결정이 \
                        한쪽에만 반영되면 앱이 보낸 board 를 서버가 거절한다.""")
                .isEqualTo(fromCode);

        String migration = readRepositoryFile("mysql/post-start/14_community.sql");
        for (String value : fromCode) {
            assertThat(migration)
                    .as("DB CHECK 가 마지막 방어선이다 (📌 #86 원칙 5) — '%s' 가 빠져 있다", value)
                    .contains("''" + value + "''");
        }
    }

    @Test
    @DisplayName("ReactionType 의 셋이 계약·서비스 상수·DB CHECK 에서 같은 문자열이다")
    void reactionTypeHasOneSpelling() {
        Set<String> fromContract = Set.copyOf(enumOf("ReactionType"));
        Set<String> fromCode = constantSet("REACTION_TYPES");

        assertThat(fromContract).isEqualTo(fromCode);

        String migration = readRepositoryFile("mysql/post-start/14_community.sql");
        for (String value : fromCode) {
            assertThat(migration)
                    .as("반응 종류도 CHECK 로 잠근다 — '%s' 가 빠져 있다", value)
                    .contains("''" + value + "''");
        }
    }

    @Test
    @DisplayName("본문 길이 상한이 계약·서버·앱 셋에서 같은 수다")
    void bodyLengthHasOneNumber() {
        int contractPostBody = maxLengthOf("PostInput", "body");
        int contractTitle = maxLengthOf("PostInput", "title");

        assertThat(contractPostBody)
                .as("""
                        2026-09-03 이전에는 이 상한이 계약에도 서버에도 없었다(#172 에서 찾음). \
                        post.body 는 TEXT 라 안 막으면 65535바이트까지 들어가고, 그 수는 컬럼 \
                        타입이 흘린 것이지 제품이 고른 것이 아니다.""")
                .isEqualTo(PostRequest.MAX_BODY_LENGTH);
        assertThat(contractTitle).isEqualTo(200);

        String repository = readRepositoryFile("../app/lib/v2/data/community_repository.dart");
        assertThat(repository)
                .as("""
                        앱의 입력칸이 이 수를 봐야 한다. 여기서 안 막으면 상한을 넘긴 사람이 \
                        올리기를 누른 뒤에야 400 을 받는다 — create_screen 이 #161 에서 같은 \
                        이유를 적어 뒀다.
                        숫자가 두 곳에 있는 것을 없앨 수는 없다(다른 언어다). 대신 갈리면 \
                        여기가 빨간불이 된다.""")
                .contains("maxBodyLength = " + PostRequest.MAX_BODY_LENGTH)
                .contains("maxTitleLength = " + contractTitle)
                .contains("maxCommentLength = " + CommentRequest.MAX_BODY_LENGTH);
    }

    // ─────────────────── D. 게스트 읽기 축 ───────────────────

    @Test
    @DisplayName("읽기 셋만 게스트를 연다 — security 에 빈 객체가 있는 오퍼레이션이 정확히 그 셋이다")
    void onlyTheThreeReadOperations_admitGuests() {
        Set<String> guestOpen = new LinkedHashSet<>();
        for (String operation : declaredOperations()) {
            if (!operation.contains("/api/community/")) {
                continue;
            }
            if (securityOf(operation).stream().anyMatch(Map::isEmpty)) {
                guestOpen.add(operation);
            }
        }

        assertThat(guestOpen)
                .as("""
                        게스트 읽기는 ADR-0016 결정 3 이다. 여기가 늘면 SecurityConfig 의 \
                        permitAll 과 ApiRateLimitFilter 의 버킷도 함께 늘어야 한다 — rate limit \
                        표에 없는 경로는 한도가 0 이 아니라 무한이다.
                        여기가 줄면 앱의 비로그인 첫 화면이 401 을 받는다.""")
                .containsExactlyInAnyOrder(
                        "GET /api/community/posts",
                        "GET /api/community/posts/{postId}",
                        "GET /api/community/posts/{postId}/comments");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /**
     * {@code api-spec.md §6} 안에서 <b>✅ 소제목</b> 아래 적힌 경로들.
     *
     * <p>인용 줄({@code >} 로 시작)은 건너뛴다. 그 자리가 <b>옛 상태를 적는 역사 서술</b>이라
     * 지금은 없는 경로가 정당하게 들어 있다 — 실제로 {@code POST /api/posts/{postId}/reactions}
     * 가 거기 있고, 안 걸러내면 이 검사는 첫 실행부터 빨간불이다.
     */
    private static List<String> endpointsClaimedAsImplemented() {
        return endpointsUnderSubsectionsMatching("✅");
    }

    /** 같은 절에서 <b>⬜ 소제목</b> 아래 적힌 경로들 — "계약에 없다" 고 선언한 것들. */
    private static List<String> endpointsMarkedAbsent() {
        return endpointsUnderSubsectionsMatching("⬜");
    }

    private static List<String> endpointsUnderSubsectionsMatching(String marker) {
        List<String> found = new ArrayList<>();
        boolean inSection = false;
        boolean inMatchingSubsection = false;

        for (String line : apiSpecRaw.split("\\R")) {
            if (line.startsWith("## ")) {
                inSection = line.startsWith(SECTION_HEADING);
                inMatchingSubsection = false;
                continue;
            }
            if (!inSection) {
                continue;
            }
            if (line.startsWith("### ")) {
                inMatchingSubsection = line.contains(marker);
                continue;
            }
            if (!inMatchingSubsection || line.stripLeading().startsWith(">")) {
                continue;
            }
            Matcher matcher = SPEC_ENDPOINT.matcher(line);
            while (matcher.find()) {
                found.add(matcher.group(1) + " " + matcher.group(2));
            }
        }
        return found;
    }

    /** {@code CommunityService} 의 값 상수. 다섯 문자열을 여기 다시 적으면 사본을 대조하게 된다. */
    @SuppressWarnings("unchecked")
    private static Set<String> constantSet(String fieldName) {
        try {
            Field field = CommunityService.class.getDeclaredField(fieldName);
            field.setAccessible(true);
            Set<String> value = (Set<String>) field.get(null);
            assertThat(value).as("%s 가 비어 있다", fieldName).isNotEmpty();
            return value;
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(
                    "CommunityService." + fieldName + " 를 못 읽었다 — 이름을 바꿨다면 여기도 고친다", e);
        }
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schema(String name) {
        Map<String, Object> components = (Map<String, Object>) spec.get("components");
        Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
        Map<String, Object> found = (Map<String, Object>) schemas.get(name);
        assertThat(found).as("계약에 %s 스키마가 없다", name).isNotNull();
        return found;
    }

    /** {@code components.schemas.<name>.properties.<field>.maxLength}. */
    @SuppressWarnings("unchecked")
    private static int maxLengthOf(String schemaName, String field) {
        Map<String, Object> properties =
                (Map<String, Object>) schema(schemaName).get("properties");
        Map<String, Object> property = (Map<String, Object>) properties.get(field);
        assertThat(property).as("계약의 %s.%s 가 없다", schemaName, field).isNotNull();

        Object maxLength = property.get("maxLength");
        assertThat(maxLength)
                .as("계약이 %s.%s 의 상한을 안 적으면 앱이 얼마까지 쓸 수 있는지 모른다", schemaName, field)
                .isInstanceOf(Integer.class);
        return (Integer) maxLength;
    }

    @SuppressWarnings("unchecked")
    private static List<String> enumOf(String schemaName) {
        List<String> values = (List<String>) schema(schemaName).get("enum");
        assertThat(values).as("%s 에 enum 이 없다", schemaName).isNotNull();
        return values;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> propertyNames(String schemaName) {
        return new LinkedHashSet<>(
                ((Map<String, Object>) schema(schemaName).get("properties")).keySet());
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> paths() {
        return (Map<String, Object>) spec.get("paths");
    }

    /** 계약이 선언한 {@code METHOD /path} 전부. */
    @SuppressWarnings("unchecked")
    private static Set<String> declaredOperations() {
        Set<String> found = new LinkedHashSet<>();
        for (var entry : paths().entrySet()) {
            for (String method : ((Map<String, Object>) entry.getValue()).keySet()) {
                if (!"parameters".equals(method)) {
                    found.add(method.toUpperCase() + " " + entry.getKey());
                }
            }
        }
        return found;
    }

    /**
     * {@code METHOD /path} 의 {@code security} 목록. 선언이 없으면 빈 목록이다.
     *
     * <p>빈 목록과 <b>빈 객체를 담은 목록</b>은 다르다. {@code security: []} 는 "인증 없이만
     * 쓴다", {@code security: [{}, {bearerAuth: []}]} 는 "있어도 되고 없어도 된다" 다.
     */
    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> securityOf(String operation) {
        int space = operation.indexOf(' ');
        String method = operation.substring(0, space).toLowerCase();
        String path = operation.substring(space + 1);

        Map<String, Object> node = (Map<String, Object>) ((Map<String, Object>) paths().get(path)).get(method);
        List<Map<String, Object>> security = (List<Map<String, Object>>) node.get("security");
        return security == null ? List.of() : security;
    }

    /** 컨트롤러의 매핑을 {@code METHOD /path} 로 눕힌다 — 클래스의 {@code @RequestMapping} 을 앞에 붙인다. */
    private static List<String> operationsOf(Class<?> controller) {
        String base = controller.isAnnotationPresent(RequestMapping.class)
                ? controller.getAnnotation(RequestMapping.class).value()[0]
                : "";
        List<String> found = new ArrayList<>();
        for (Method method : controller.getDeclaredMethods()) {
            if (method.isAnnotationPresent(GetMapping.class)) {
                found.add("GET " + base + method.getAnnotation(GetMapping.class).value()[0]);
            }
            if (method.isAnnotationPresent(PostMapping.class)) {
                found.add("POST " + base + method.getAnnotation(PostMapping.class).value()[0]);
            }
            if (method.isAnnotationPresent(DeleteMapping.class)) {
                found.add("DELETE " + base + method.getAnnotation(DeleteMapping.class).value()[0]);
            }
        }
        return found;
    }

    /** 응답 레코드의 필드 이름. Jackson 이 그대로 JSON 키로 쓴다. */
    private static Set<String> componentNames(Class<?> record) {
        Set<String> names = new LinkedHashSet<>();
        for (RecordComponent component : record.getRecordComponents()) {
            names.add(component.getName());
        }
        return names;
    }

    private static String readRepositoryFile(String relativePath) {
        try {
            return Files.readString(
                    TestProjectPaths.requireFile(relativePath), StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new IllegalStateException(relativePath + " 를 읽지 못했다", e);
        }
    }
}
