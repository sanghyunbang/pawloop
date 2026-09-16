package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.care.controller.CareItemController;
import com.heattrip.heat_trip_backend.care.dto.CareItemOrderRequest;
import com.heattrip.heat_trip_backend.care.dto.CareItemRequest;
import com.heattrip.heat_trip_backend.care.dto.CareItemResponse;
import com.heattrip.heat_trip_backend.care.entity.CareIcon;
import com.heattrip.heat_trip_backend.care.entity.CareType;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.lang.annotation.Annotation;
import java.lang.reflect.Method;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 케어 <b>항목</b> 계약이 실제로 도는 코드와 같은 것을 말하는지 본다 — 이슈 #560 조각 2.
 *
 * <h2>왜 {@code CareContractSpecTest} 에 안 붙이나</h2>
 *
 * <p>거기는 <b>기록</b>의 계약이고 여기는 <b>목록</b>의 계약이다. 무엇보다 그 파일은
 * {@code CareController} 의 매핑이 <b>정확히 다섯</b>인지를 잰다 — 한 파일에 섞으면 그 수가
 * 열이 되고, 그러면 "무엇이 깨졌나" 를 세 보고 알아내야 한다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 문서를 읽고 클래스를 리플렉션으로 볼 뿐이다(#21).
 * 실제로 부르는 것은 {@code CareItemApiIntegrationTest} 다 — 계약이 맞아도 라우팅이 틀릴 수
 * 있어서 둘이 서로를 대신하지 않는다.
 */
class CareItemContractSpecTest {

    private static final String BASE = "/api/groups/{groupId}/care-items";

    private static Map<String, Object> spec;

    @SuppressWarnings("unchecked")
    @BeforeAll
    static void loadContract() throws IOException {
        // 파일이 없으면 requireFile 이 여기서 던진다. skip 이 아니다 — 못 읽고 통과하면
        // 이 테스트는 아무것도 지키지 않으면서 초록불만 낸다.
        String raw = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);
        spec = (Map<String, Object>) new Yaml().load(raw);
    }

    // ─────────────────── A. 코드 ↔ 계약 ───────────────────

    @Test
    @DisplayName("컨트롤러의 다섯 매핑이 계약에 그대로 등재돼 있다 — 경로 목록은 컨트롤러에서 읽는다")
    void everyMapping_isDeclaredInTheContract() {
        List<String> implemented = operationsOf(CareItemController.class);

        assertThat(implemented)
                .as("컨트롤러에서 매핑을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .hasSize(5);
        assertThat(declaredOperations())
                .as("""
                        계약에 없는 경로는 앱이 존재를 모른다 — design-first 라 앱은 이 파일을 보고 만든다.
                        경로 변수 이름까지 같아야 한다: 계약이 {itemId} 인데 코드가 {id} 면 생성된 \
                        클라이언트의 시그니처가 틀린다.""")
                .containsAll(implemented);
    }

    @Test
    @DisplayName("순서 경로가 항목 경로와 따로 선언돼 있다 — order 가 itemId 로 읽히면 안 된다")
    void theOrderPathIsItsOwnEntry() {
        assertThat(paths())
                .as("""
                        /care-items/order 를 따로 안 적고 {itemId} 하나로 두면, 앱이 보낸 'order' 를 \
                        서버가 long 으로 읽으려다 400 을 낸다. 계약이 둘을 갈라 놓아야 앱도 둘로 만든다.""")
                .containsKey(BASE + "/order")
                .containsKey(BASE + "/{itemId}");
    }

    // ─────────────────── B. 모양 ───────────────────

    @Test
    @DisplayName("CareItem 200 의 속성 집합이 CareItemResponse 의 필드 집합과 정확히 같다")
    void careItemSchema_matchesTheResponseRecord() {
        assertThat(propertyNames("CareItem"))
                .as("""
                        계약과 응답 DTO 가 갈리면 앱이 없는 필드를 읽거나 있는 필드를 모른다. \
                        여기서 이름을 손으로 적지 않고 레코드에서 읽는 이유가 그것이다.""")
                .containsExactlyInAnyOrderElementsOf(componentNames(CareItemResponse.class));
    }

    @Test
    @DisplayName("CareItemInput 이 요청 레코드와 같고, sortOrder·systemType 은 없다")
    void careItemInput_matchesTheRequestRecord() {
        assertThat(propertyNames("CareItemInput"))
                .as("""
                        갈리면 앱이 보낸 필드를 서버가 조용히 버린다 — #563 이 요청 쪽을 안 대조하다 \
                        겪은 자리다.""")
                .containsExactlyInAnyOrderElementsOf(componentNames(CareItemRequest.class));

        assertThat(propertyNames("CareItemInput"))
                .as("""
                        sortOrder 를 받으면 '한 항목만 3번' 이 되고 나머지가 어떻게 밀리는지를 서버가 \
                        지어내야 한다 — 순서는 /order 가 목록 전체로 정한다.
                        systemType 을 받으면 직접 만든 항목이 옛 기록을 가져가고, 그 순간 지난 기록이 \
                        통째로 다른 칸으로 옮겨 간다.""")
                .doesNotContain("sortOrder", "systemType", "id");

        assertThat(requiredOf("CareItemInput"))
                .as("이름과 아이콘 없이 만들 수 있으면 칸에 그릴 것이 없다")
                .containsExactlyInAnyOrder("name", "icon");
    }

    @Test
    @DisplayName("CareItemOrderInput 이 요청 레코드와 같다 — 목록 전체를 받는다")
    void orderInput_matchesTheRequestRecord() {
        assertThat(propertyNames("CareItemOrderInput"))
                .containsExactlyInAnyOrderElementsOf(componentNames(CareItemOrderRequest.class));
        assertThat(requiredOf("CareItemOrderInput")).containsExactly("itemIds");
    }

    @SuppressWarnings("unchecked")
    @Test
    @DisplayName("CareIcon 의 값이 계약과 enum 에서 같고, 앞의 일곱은 CareType 의 표기 그대로다")
    void careIconHasOneSpelling() {
        List<String> fromContract = (List<String>) schema("CareIcon").get("enum");
        List<String> fromCode = Arrays.stream(CareIcon.values()).map(CareIcon::wire).toList();

        assertThat(fromContract)
                .as("""
                        같은 값에 표기가 둘이면 앱이 그림을 못 고른다. 자바 상수 이름(WATER)이 아니라 \
                        wire 값(water)이 계약과 같아야 한다.""")
                .isEqualTo(fromCode);

        assertThat(fromCode.subList(0, CareType.values().length))
                .as("""
                        기본 일곱은 제 종류를 아이콘으로 쓴다(CareItem.defaultsFor). 두 목록이 갈리면 \
                        가족을 만들자마자 일곱 칸 중 몇 개가 기본 그림으로 떨어진다.""")
                .isEqualTo(Arrays.stream(CareType.values()).map(CareType::wire).toList());
    }

    // ─────────────────── C. 한도와 인가 ───────────────────

    @Test
    @DisplayName("쓰기 넷만 429 를 선언한다 — 읽기는 rate limit 표 밖이라는 것을 계약도 말한다")
    void onlyTheWritePathsDeclareRateLimiting() {
        assertThat(statusCodesOf(BASE, "post")).contains("429");
        assertThat(statusCodesOf(BASE + "/order", "put")).contains("429");
        assertThat(statusCodesOf(BASE + "/{itemId}", "put")).contains("429");
        assertThat(statusCodesOf(BASE + "/{itemId}", "delete")).contains("429");

        assertThat(statusCodesOf(BASE, "get"))
                .as("""
                        읽기는 ApiRateLimitFilter.resolveRule 의 표에 없다 — 즉 한도가 0 이 아니라 \
                        무한이다. 계약이 429 를 선언하면 앱은 있지도 않은 한도를 다루는 코드를 짠다.""")
                .doesNotContain("429");
    }

    @Test
    @DisplayName("다섯 경로 모두 401·403 을 선언한다 — 남의 집 목록은 안 보인다")
    void everyPathDeclaresAuthFailures() {
        for (String path : List.of(BASE, BASE + "/order", BASE + "/{itemId}")) {
            for (String method : methodsOf(path)) {
                assertThat(statusCodesOf(path, method))
                        .as("%s %s — 그 그룹의 방 멤버가 아니면 403 이다", method, path)
                        .contains("403", "401");
            }
        }
    }

    @Test
    @DisplayName("항목 경로 둘은 404 를 선언한다 — 옆집 항목과 없는 항목이 같은 답이다")
    void theItemPathsDeclareNotFound() {
        assertThat(statusCodesOf(BASE + "/{itemId}", "put"))
                .as("403 을 주면 '그 id 는 존재한다' 를 알려 주는 셈이 된다(#209)")
                .contains("404");
        assertThat(statusCodesOf(BASE + "/{itemId}", "delete")).contains("404");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    @SuppressWarnings("unchecked")
    private static Map<String, Object> paths() {
        return (Map<String, Object>) spec.get("paths");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schema(String name) {
        Map<String, Object> components = (Map<String, Object>) spec.get("components");
        Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
        Map<String, Object> found = (Map<String, Object>) schemas.get(name);
        assertThat(found).as("계약에 %s 스키마가 없다", name).isNotNull();
        return found;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> propertyNames(String schemaName) {
        return new LinkedHashSet<>(
                ((Map<String, Object>) schema(schemaName).get("properties")).keySet());
    }

    @SuppressWarnings("unchecked")
    private static List<String> requiredOf(String schemaName) {
        return (List<String>) schema(schemaName).get("required");
    }

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

    @SuppressWarnings("unchecked")
    private static List<String> methodsOf(String path) {
        return ((Map<String, Object>) paths().get(path)).keySet().stream()
                .filter(key -> !"parameters".equals(key))
                .toList();
    }

    @SuppressWarnings("unchecked")
    private static Set<String> statusCodesOf(String path, String method) {
        Map<String, Object> operation =
                (Map<String, Object>) ((Map<String, Object>) paths().get(path)).get(method);
        assertThat(operation).as("계약에 %s %s 가 없다", method, path).isNotNull();
        return ((Map<String, Object>) operation.get("responses")).keySet();
    }

    /**
     * 컨트롤러의 매핑을 {@code METHOD /path} 로 눕힌다.
     *
     * <p>{@code CareContractSpecTest} 의 같은 이름 지그는 {@code value()[0]} 을 그냥 읽는다 —
     * 이 컨트롤러는 <b>값 없는</b> {@code @GetMapping} 을 쓰므로 거기서는 터진다. 클래스의
     * {@code @RequestMapping} 이 이미 전체 경로라서 값이 빌 수 있는 것이 정상이다.
     */
    private static List<String> operationsOf(Class<?> controller) {
        String base = controller.isAnnotationPresent(RequestMapping.class)
                ? controller.getAnnotation(RequestMapping.class).value()[0]
                : "";
        List<String> found = new ArrayList<>();
        for (Method method : controller.getDeclaredMethods()) {
            add(found, "GET", base, method.getAnnotation(GetMapping.class));
            add(found, "POST", base, method.getAnnotation(PostMapping.class));
            add(found, "PUT", base, method.getAnnotation(PutMapping.class));
            add(found, "DELETE", base, method.getAnnotation(DeleteMapping.class));
        }
        return found;
    }

    private static void add(List<String> found, String verb, String base, Annotation mapping) {
        if (mapping == null) {
            return;
        }
        String[] value = switch (verb) {
            case "GET" -> ((GetMapping) mapping).value();
            case "POST" -> ((PostMapping) mapping).value();
            case "PUT" -> ((PutMapping) mapping).value();
            default -> ((DeleteMapping) mapping).value();
        };
        found.add(verb + " " + base + (value.length == 0 ? "" : value[0]));
    }

    /** 레코드의 필드 이름. Jackson 이 그대로 JSON 키로 쓴다. */
    private static Set<String> componentNames(Class<?> record) {
        Set<String> names = new LinkedHashSet<>();
        for (RecordComponent component : record.getRecordComponents()) {
            names.add(component.getName());
        }
        return names;
    }
}
