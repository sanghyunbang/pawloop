package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
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

import com.heattrip.heat_trip_backend.place.controller.PlaceController;
import com.heattrip.heat_trip_backend.place.dto.PlaceDto;
import com.heattrip.heat_trip_backend.security.ApiRateLimitFilter;
import com.heattrip.heat_trip_backend.security.RateLimitProperties;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Places 계약이 <b>도는 코드</b>와 같은 것을 말하는지 본다 — 이슈 #210.
 *
 * <h2>왜 필요한가</h2>
 * <p><b>Places 에는 계약 스펙 테스트가 아예 없었다.</b> {@code contract/} 에 Auth·Care·Chat·
 * FamilyGroup·Community 는 있는데 Places 만 없었고, 그래서 <b>서버가 실제로 던지는 상태코드가
 * 계약에 없는</b> 드리프트를 아무도 안 잡았다.
 *
 * <p>2026-08 감사 때는 '선언 누락' 이었다. 그 사이 구현이 붙으면서 성격이 바뀌었다 — 이제는
 * {@code ApiRateLimitFilter} 가 {@code /api/places/{contentId}} 를 {@code places-detail}
 * 버킷에 걸어 <b>실제로 429 를 던지는데</b> 계약에는 200·404 뿐이었다. 앱은 그걸 일반 실패로
 * 뭉갠다.
 *
 * <h2>무엇을 재는가</h2>
 * <ul>
 *   <li><b>필터 ↔ 계약</b> — 필터가 버킷에 거는 경로는 계약이 {@code 429} 를 선언해야 한다.
 *       <b>필터를 실제로 돌려서</b> 확인한다. 규칙 문자열을 손으로 옮겨 적으면 사본과 문서를
 *       대조하는 셈이라 둘이 나란히 낡는다.</li>
 *   <li><b>컨트롤러 ↔ 계약</b> — 매핑 경로와 응답 레코드의 필드.</li>
 *   <li><b>계약 ↔ 코드</b> — {@code PlaceCategory} enum 과 {@code PlaceDto.KNOWN_CATEGORIES}.</li>
 * </ul>
 *
 * <p>스프링 컨텍스트를 띄우지 않는다(#21).
 */
class PlacesContractSpecTest {

    private static Map<String, Object> spec;
    private static String apiSpecRaw;

    private static final String NEARBY = "/api/places/nearby";
    private static final String DETAIL = "/api/places/{contentId}";

    /** {@code api-spec.md} 의 장소 절. 여기 적힌 경로가 계약과 같아야 한다. */
    private static final String SECTION_HEADING = "## 4. 장소";

    /** {@code GET /api/places/nearby?lat=...} 꼴. 물음표 앞까지가 경로다. */
    private static final Pattern SPEC_ENDPOINT =
            Pattern.compile("(GET|POST|PATCH|PUT|DELETE)\\s+(/api/places/[^\\s`?]*)");

    /** JSON 예시의 키. 값 쪽 문자열이나 주석은 안 잡는다. */
    private static final Pattern JSON_KEY = Pattern.compile("^\\s*\"([A-Za-z][A-Za-z0-9_]*)\"\\s*:");

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() {
        // 파일이 없으면 requireFile 이 여기서 던진다. skip 이 아니다 — 못 읽고 통과하면
        // 이 테스트는 아무것도 지키지 않으면서 초록불만 낸다.
        spec = (Map<String, Object>) new Yaml().load(readRepositoryFile("../docs/04-api/openapi.yaml"));
        apiSpecRaw = readRepositoryFile("../docs/04-api/api-spec.md");
    }

    // ─────────────────── A. 필터 ↔ 계약 ───────────────────

    @Test
    @DisplayName("레이트리밋 버킷에 걸리는 Places 경로는 계약이 429 를 선언한다 — 필터를 실제로 돌려서 본다")
    void everyRateLimitedPlacesPath_declares429() throws Exception {
        // 한도를 1 로 두고 같은 경로를 두 번 부르면 버킷에 걸린 경로만 429 가 된다.
        assertThat(secondCallStatus("/api/places/nearby"))
                .as("목록이 버킷에 안 걸려 있다면 이 테스트의 전제가 무너진다 — 그때는 필터를 봐야 한다")
                .isEqualTo(429);
        assertThat(secondCallStatus("/api/places/126535"))
                .as("상세도 마찬가지다")
                .isEqualTo(429);

        assertThat(declaredStatuses(NEARBY)).contains("429");
        assertThat(declaredStatuses(DETAIL))
                .as("상세는 KTO 를 1건에 2콜 쓴다. 목록보다 좁은 places-detail 버킷이고 서버가"
                        + " 실제로 던지는데, 2026-09-03 이전에는 계약에만 없었다 (#210).")
                .contains("429");
    }

    @Test
    @DisplayName("숫자가 아닌 contentId 도 상세 버킷이 덮는다 — 좁히면 한도 없는 KTO 경로가 생긴다")
    void detailBucketCoversNonNumericIds() throws Exception {
        assertThat(secondCallStatus("/api/places/abc")).isEqualTo(429);
    }

    @Test
    @DisplayName("산책로 선 경로도 버킷에 걸리고 계약이 429 를 선언한다 — permitAll 이 셋째 경로를 열었다 (#291)")
    void trailRouteIsMeteredAndDeclares429() throws Exception {
        assertThat(secondCallStatus("/api/places/trails/T_ROUTE_1/route")).isEqualTo(429);
        assertThat(declaredStatuses("/api/places/trails/{courseId}/route")).contains("429", "404");
    }

    // ─────────────────── B. 코드 ↔ 계약 ───────────────────

    @Test
    @DisplayName("컨트롤러의 매핑이 전부 계약에 등재돼 있다 — 경로는 코드에서 읽는다")
    void everyImplementedEndpoint_isDeclaredInTheContract() {
        List<String> implemented = operationsOf(PlaceController.class);

        assertThat(implemented)
                .as("컨트롤러에서 매핑을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isNotEmpty();
        assertThat(declaredOperations()).containsAll(implemented);
    }

    @Test
    @DisplayName("Place 스키마의 속성이 PlaceDto 의 필드와 정확히 같다")
    void placeSchema_matchesTheResponseRecord() {
        assertThat(propertyNames("Place"))
                .as("계약과 응답 DTO 가 갈리면 앱이 없는 필드를 읽거나 있는 필드를 모른다")
                .containsExactlyInAnyOrderElementsOf(componentNames(PlaceDto.class));
    }

    @Test
    @DisplayName("좌표는 계약에 범위가 있고 서버가 그 밖을 400 으로 막는다 — radius·limit 과 다른 태도다")
    void coordinatesHaveBoundsAndAreRejected() {
        assertThat(parameterSchema(NEARBY, "lat"))
                .containsEntry("minimum", -90)
                .containsEntry("maximum", 90);
        assertThat(parameterSchema(NEARBY, "lng"))
                .containsEntry("minimum", -180)
                .containsEntry("maximum", 180);

        assertThat(declaredStatuses(NEARBY))
                .as("서버가 requireFinite 와 범위 검사로 실제 400 을 던진다. radius·limit 은 자르는데"
                        + " 좌표만 거절하는 것이 의도다 — 조용히 다른 지점의 답을 주면 사용자는"
                        + " 자기 주변이 비었다고 읽는다 (#210).")
                .contains("400");
    }

    // ─────────────────── C. 값의 출처 ───────────────────

    @Test
    @DisplayName("PlaceCategory 의 KTO 값과 PlaceDto.KNOWN_CATEGORIES 가 같은 집합이다")
    void categoryValuesHaveOneSource() {
        Set<String> fromContract = new LinkedHashSet<>(enumOf("PlaceCategory"));
        // 레이어 키는 KTO 의 contentTypeId 가 아니다 — 서버가 source 로 채운다.
        // 넷째(playground)는 #346 에서 왔다.
        fromContract.removeAll(PlaceDto.LAYER_SOURCES);

        assertThat(fromContract)
                .as("갈리면 KTO 가 준 값을 서버가 그대로 실어 보내고 앱이 라벨을 못 찾아 빈 칸이 된다."
                        + " 이 목록이 세 군데에 복사돼 있던 것이 #210 Places-low-1 이고,"
                        + " 지금은 PlaceDto 한 곳이다.")
                .isEqualTo(PlaceDto.KNOWN_CATEGORIES);
    }

    @Test
    @DisplayName("contentTypeId 는 null 이 될 수 있다 — kto 가 아닌 출처에는 채울 값이 없다")
    void contentTypeIdIsNullable() {
        assertThat(typeOf("Place", "contentTypeId")).contains("null");
    }

    // ─────────────────── D. api-spec.md ↔ 계약 ───────────────────

    @Test
    @DisplayName("api-spec.md §4 가 구현됐다고 적은 경로가 전부 계약에 있다")
    void apiSpecSection_onlyClaimsPathsTheContractDeclares() {
        // openapi.yaml 만 고치면 api-spec.md 에 같은 거짓 서술이 남는다. #167 이 §6 에서
        // 찾은 것이 정확히 그 상태였고, 그 장치가 Places 에는 없었다 (#210).
        List<String> claimed = endpointsUnderSubsectionsMatching("✅");

        assertThat(claimed)
                .as("§4 에서 ✅ 절의 경로를 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isNotEmpty();
        assertThat(declaredOperations()).containsAll(claimed);
    }

    @Test
    @DisplayName("api-spec.md §4 의 상세 예시가 계약에 없는 필드를 적지 않는다")
    void apiSpecExample_doesNotInventFields() {
        // 2026-09-03 이전 §4.3 예시는 acmpyPsblCpam 을 두 번 적고 petFacility·homepage·
        // openHours·updatedAt 넷을 달고 있었다. 그대로 짜면 앱이 없는 필드를 읽는다.
        Set<String> known = new LinkedHashSet<>(propertyNames("Place"));
        known.addAll(placeDetailExtraProperties());
        known.addAll(petInfoProperties());

        for (String key : jsonKeysUnder("### 4.3")) {
            assertThat(known)
                    .as("§4.3 예시의 '%s' 가 계약의 PlaceDetail 에 없다".formatted(key))
                    .contains(key);
        }
    }

    // ─────────────────── 도구 ───────────────────

    /**
     * 한도 1 짜리 필터로 같은 경로를 두 번 부른 뒤의 상태코드.
     *
     * <p>버킷에 걸린 경로면 429, 아니면 200 이다. <b>규칙을 손으로 옮겨 적지 않으려고</b>
     * 필터를 실제로 돌린다.
     */
    private static int secondCallStatus(String path) throws Exception {
        RateLimitProperties props = new RateLimitProperties();
        props.setEnabled(true);
        props.setWindowSeconds(60);
        props.setPlacesMaxRequests(1);
        props.setPlacesDetailMaxRequests(1);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(props, new ObjectMapper());

        call(filter, path);
        return call(filter, path).getStatus();
    }

    private static MockHttpServletResponse call(ApiRateLimitFilter filter, String path) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", path);
        request.setRemoteAddr("203.0.113.9");
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        return response;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> declaredStatuses(String path) {
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");
        Map<String, Object> item = (Map<String, Object>) paths.get(path);
        Map<String, Object> get = (Map<String, Object>) item.get("get");
        return ((Map<String, Object>) get.get("responses")).keySet();
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> parameterSchema(String path, String name) {
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");
        Map<String, Object> get = (Map<String, Object>) ((Map<String, Object>) paths.get(path)).get("get");
        for (Map<String, Object> parameter : (List<Map<String, Object>>) get.get("parameters")) {
            if (name.equals(parameter.get("name"))) {
                return (Map<String, Object>) parameter.get("schema");
            }
        }
        throw new AssertionError(path + " 에 " + name + " 파라미터가 없다");
    }

    @SuppressWarnings("unchecked")
    private static Set<String> declaredOperations() {
        Set<String> found = new LinkedHashSet<>();
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");
        paths.forEach((path, item) -> ((Map<String, Object>) item).keySet().stream()
                .filter(key -> Set.of("get", "post", "patch", "put", "delete").contains(key))
                .forEach(method -> found.add(method.toUpperCase() + " " + path)));
        return found;
    }

    /** 컨트롤러의 매핑을 {@code METHOD /path} 로 눕힌다. */
    private static List<String> operationsOf(Class<?> controller) {
        String base = controller.isAnnotationPresent(RequestMapping.class)
                ? controller.getAnnotation(RequestMapping.class).value()[0]
                : "";
        List<String> found = new ArrayList<>();
        for (Method method : controller.getDeclaredMethods()) {
            if (method.isAnnotationPresent(GetMapping.class)) {
                found.add("GET " + base + method.getAnnotation(GetMapping.class).value()[0]);
            }
        }
        return found;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> propertyNames(String schema) {
        Map<String, Object> schemas =
                (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");
        return ((Map<String, Object>) ((Map<String, Object>) schemas.get(schema)).get("properties")).keySet();
    }

    @SuppressWarnings("unchecked")
    private static List<String> typeOf(String schema, String property) {
        Map<String, Object> schemas =
                (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");
        Map<String, Object> props =
                (Map<String, Object>) ((Map<String, Object>) schemas.get(schema)).get("properties");
        Object type = ((Map<String, Object>) props.get(property)).get("type");
        return type instanceof List ? (List<String>) type : List.of(String.valueOf(type));
    }

    @SuppressWarnings("unchecked")
    private static List<String> enumOf(String schema) {
        Map<String, Object> schemas =
                (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");
        return (List<String>) ((Map<String, Object>) schemas.get(schema)).get("enum");
    }

    private static Set<String> componentNames(Class<?> record) {
        Set<String> names = new LinkedHashSet<>();
        for (RecordComponent component : record.getRecordComponents()) {
            names.add(component.getName());
        }
        return names;
    }

    /** {@code api-spec.md} 의 장소 절에서 마커가 붙은 소절의 경로를 읽는다. */
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

    /** 소절 하나의 JSON 예시에 등장하는 키. 주석 뒤는 무시한다. */
    private static Set<String> jsonKeysUnder(String subsectionPrefix) {
        Set<String> keys = new LinkedHashSet<>();
        boolean inSubsection = false;
        for (String line : apiSpecRaw.split("\\R")) {
            if (line.startsWith("### ")) {
                inSubsection = line.startsWith(subsectionPrefix);
                continue;
            }
            if (!inSubsection) {
                continue;
            }
            Matcher matcher = JSON_KEY.matcher(line);
            while (matcher.find()) {
                keys.add(matcher.group(1));
            }
        }
        if (keys.isEmpty()) {
            throw new AssertionError(subsectionPrefix + " 아래에서 JSON 키를 하나도 못 읽었다");
        }
        return keys;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> placeDetailExtraProperties() {
        Map<String, Object> schemas =
                (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");
        List<Map<String, Object>> allOf =
                (List<Map<String, Object>>) ((Map<String, Object>) schemas.get("PlaceDetail")).get("allOf");
        for (Map<String, Object> part : allOf) {
            if (part.containsKey("properties")) {
                return ((Map<String, Object>) part.get("properties")).keySet();
            }
        }
        throw new AssertionError("PlaceDetail 의 allOf 에서 properties 를 못 찾았다");
    }

    @SuppressWarnings("unchecked")
    private static Set<String> petInfoProperties() {
        Map<String, Object> schemas =
                (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");
        List<Map<String, Object>> allOf =
                (List<Map<String, Object>>) ((Map<String, Object>) schemas.get("PlaceDetail")).get("allOf");
        for (Map<String, Object> part : allOf) {
            if (part.containsKey("properties")) {
                Map<String, Object> props = (Map<String, Object>) part.get("properties");
                Map<String, Object> petInfo = (Map<String, Object>) props.get("petInfo");
                return ((Map<String, Object>) petInfo.get("properties")).keySet();
            }
        }
        throw new AssertionError("petInfo 의 properties 를 못 찾았다");
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
