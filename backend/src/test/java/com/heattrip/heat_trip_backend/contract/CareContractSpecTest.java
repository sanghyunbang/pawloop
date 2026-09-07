package com.heattrip.heat_trip_backend.contract;

import com.heattrip.heat_trip_backend.care.controller.CareController;
import com.heattrip.heat_trip_backend.care.dto.CareLogResponse;
import com.heattrip.heat_trip_backend.care.dto.WalkNoteResponse;
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
 * 케어 계약이 <b>실제로 도는 코드</b>와 같은 것을 말하는지 본다 — 이슈 #76.
 *
 * <h2>이 이슈가 계약에서 고친 것</h2>
 * <p>네 경로는 계약에 <b>선언만</b> 되어 있었고 구현이 없었다. 선언만 있는 동안 아무도 안
 * 보는 사이에 셋이 실제와 어긋나 있었다.
 * <ul>
 *   <li><b>{@code CareLogInput.dogId} 가 필수</b>였다 — {@code dog} 표가 정본 스키마에 없어서
 *       서버가 검증할 수 있는 강아지 id 자체가 없다. 필수로 두면 앱이 더미 id 를 지어내야 한다.</li>
 *   <li><b>{@code CareLogInput.occurredAt}</b> 이 있었다 — 그 값이 곧 "오늘 누가 했는지" 를
 *       가르는 기준이라 클라이언트가 정하면 화면 문구를 믿을 수 없다.</li>
 *   <li><b>{@code walk-notes} 가 목록</b>이었다({@code {notes:[...]}} 전량 교체). 이슈가 정한
 *       표는 그룹당 한 장이고, 목록 전량 교체는 {@code updatedBy} 를 무의미하게 만든다.</li>
 * </ul>
 *
 * <h2>경로와 필드를 손으로 적지 않는다</h2>
 * <p>경로는 컨트롤러의 애너테이션에서, 응답 필드는 레코드 컴포넌트에서 읽는다. 손으로 적으면
 * 코드가 아니라 <b>사본과 문서</b>를 대조하게 되어 둘이 나란히 낡은 채 초록불이 된다
 * ({@code FamilyGroupContractSpecTest} 가 같은 이유로 그렇게 한다).
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 문서를 읽고 클래스를 리플렉션으로 볼 뿐이다(#21).
 */
class CareContractSpecTest {

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
    @DisplayName("이 이슈가 연 네 경로와 #209 의 삭제가 계약에 그대로 등재돼 있다 — 경로 목록은 컨트롤러에서 읽는다")
    void everyEndpointThisIssueOpened_isDeclaredInTheContract() {
        List<String> implemented = operationsOf(CareController.class);

        assertThat(implemented)
                .as("컨트롤러에서 매핑을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .hasSize(5);
        assertThat(declaredOperations())
                .as("""
                        계약에 없는 경로는 앱이 존재를 모른다 — design-first 라 앱은 이 파일을 보고 만든다.
                        경로 변수 이름까지 같아야 한다: 계약이 {groupId} 인데 코드가 {id} 면 생성된 \
                        클라이언트의 시그니처가 틀린다.""")
                .containsAll(implemented);
    }

    @Test
    @DisplayName("CareType 의 일곱 값이 계약·enum·DB CHECK 에서 같은 문자열이다")
    void careTypeHasOneSpelling() {
        List<String> fromContract = (List<String>) schema("CareType").get("enum");
        List<String> fromCode = Arrays.stream(CareType.values()).map(CareType::wire).toList();

        assertThat(fromContract)
                .as("""
                        같은 값에 표기가 둘이면 어느 쪽이 정본인지 매번 물어야 한다. #75 가 \
                        GroupRole 의 대소문자 두 벌을 걷어낸 것과 같은 자리다.
                        자바 상수 이름(WATER)이 아니라 wire 값(water)이 계약과 같아야 한다 — \
                        @Enumerated(STRING) 을 쓰면 이 단언이 빨간불이다.""")
                .isEqualTo(fromCode);

        // CHECK 의 정본이 두 파일에 걸쳐 있다 — 08 이 다섯을 만들고 29 가 poop·pee 를 더한다(#340).
        // 그래서 "어느 한 스크립트에는 있다" 로 잰다. 08 에만 대면 새 값이 영원히 빨간불이고,
        // 29 에만 대면 옛 다섯이 검사에서 빠진다.
        String migration = readRepositoryFile("mysql/post-start/08_care_log.sql")
                + readRepositoryFile("mysql/post-start/29_care_type_poop.sql");
        for (String value : fromCode) {
            assertThat(migration)
                    .as("DB CHECK 가 마지막 방어선이다 (📌 #86 원칙 5) — '%s' 가 빠져 있다", value)
                    .contains("'" + value + "'");
        }
    }

    // ─────────────────── B. 응답 모양 ───────────────────

    @Test
    @DisplayName("CareLog 200 의 속성 집합이 CareLogResponse 의 필드 집합과 정확히 같다")
    void careLogSchema_matchesTheResponseRecord() {
        assertThat(propertyNames("CareLog"))
                .as("""
                        계약과 응답 DTO 가 갈리면 앱이 없는 필드를 읽거나 있는 필드를 모른다. \
                        여기서 이름을 손으로 적지 않고 레코드에서 읽는 이유가 그것이다.""")
                .containsExactlyInAnyOrderElementsOf(componentNames(CareLogResponse.class));

        assertThat(propertyNames("CareDoer"))
                .as("이름만으로는 '나' 와 '아빠' 를 가를 수 없다 — userId 가 함께 있어야 한다")
                .containsExactlyInAnyOrder("userId", "nickname");
    }

    @Test
    @DisplayName("CareLogInput 에 dogId·occurredAt·doneBy·위치가 없고 type 만 필수다")
    void careLogInput_letsTheServerDecideWhoAndWhen() {
        Map<String, Object> input = schema("CareLogInput");

        assertThat(propertyNames("CareLogInput"))
                .as("""
                        dogId 는 확인할 표가 없다 — dog 표가 정본 스키마에 없어 검증할 수 없는 외래 \
                        id 를 저장하면 아무도 해석 못 하는 값이 남고, 필수로 두면 앱이 더미 id 를 \
                        지어내야 한다.
                        occurredAt·doneBy 는 서버가 정한다 — 그 둘이 '오늘 누가 했는지' 를 가르는 \
                        기준이라 클라이언트가 정하면 남의 화면에 없던 기록을 만들어 넣을 수 있다.
                        위치도 없다 — 배변·마킹(#340)은 산책 중에 눌리지만 어디서 눴는지는 \
                        기기에만 남는다(A안 #235). 이 목록에 좌표 키가 생기면 그 약속이 깨진다.""")
                .containsExactly("type", "memo");
        assertThat((List<String>) input.get("required")).containsExactly("type");
    }

    // ─────────────────── C. walk-notes 는 목록이 아니다 ───────────────────

    @Test
    @DisplayName("WalkNote 는 배열이 아니라 객체 하나다 — 그룹당 한 장이기 때문이다")
    void walkNotes_areOneSheetNotAList() {
        assertThat(responseSchema("/api/groups/{groupId}/walk-notes", "get"))
                .as("""
                        2026-08 이전 계약은 배열이었다. 목록을 전량 교체로 다루면 PUT 때마다 행을 \
                        지우고 다시 넣게 되어 행마다 붙는 updatedBy 가 아무것도 가리키지 않는다 \
                        (이슈 #76 이 표를 그룹당 한 장으로 정했다).""")
                .containsEntry("$ref", "#/components/schemas/WalkNote");

        assertThat(propertyNames("WalkNote"))
                .as("id 는 싣지 않는다 — 그룹당 한 장이라 그 id 로 갈 수 있는 경로가 없다")
                .containsExactlyInAnyOrderElementsOf(componentNames(WalkNoteResponse.class));

        assertThat(propertyNames("WalkNoteInput"))
                .as("{notes:[...]} 가 남아 있으면 앱이 보낸 본문을 서버가 읽지 못한다")
                .containsExactly("body");
    }

    @Test
    @DisplayName("쓰기 셋만 429 를 선언한다 — 읽기는 rate limit 표 밖이라는 것을 계약도 말한다")
    void onlyTheWritePathsDeclareRateLimiting() {
        assertThat(statusCodesOf("/api/groups/{groupId}/care-logs", "post")).contains("429");
        assertThat(statusCodesOf("/api/groups/{groupId}/walk-notes", "put")).contains("429");
        assertThat(statusCodesOf("/api/groups/{groupId}/care-logs/{careLogId}", "delete"))
                .as("삭제도 group-write 다(#209) — ApiRateLimitFilterTest 가 필터 쪽을 잰다")
                .contains("429");

        assertThat(statusCodesOf("/api/groups/{groupId}/care-logs", "get"))
                .as("""
                        읽기 둘은 ApiRateLimitFilter.resolveRule 의 표에 없다 — 즉 한도가 0 이 아니라 \
                        무한이다. 계약이 429 를 선언하면 앱은 있지도 않은 한도를 다루는 코드를 짠다.
                        미룬 것이지 안전한 것이 아니고, 숫자는 앱의 폴링 주기가 정해지는 M2.6 에서 \
                        함께 정한다.""")
                .doesNotContain("429");
        assertThat(statusCodesOf("/api/groups/{groupId}/walk-notes", "get")).doesNotContain("429");
    }

    @Test
    @DisplayName("다섯 경로 모두 403 을 선언한다 — 인가가 이 이슈의 핵심이다")
    void allFourPathsDeclareForbidden() {
        for (String path : List.of("/api/groups/{groupId}/care-logs",
                "/api/groups/{groupId}/care-logs/{careLogId}",
                "/api/groups/{groupId}/walk-notes")) {
            for (String method : methodsOf(path)) {
                assertThat(statusCodesOf(path, method))
                        .as("%s %s — 그 그룹의 방 멤버가 아니면 403 이다(완료 조건 3)", method, path)
                        .contains("403", "401");
            }
        }
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
        return ((Map<String, Object>) operation.get("responses")).keySet();
    }

    /** {@code 200} 응답의 JSON 스키마 노드. */
    @SuppressWarnings("unchecked")
    private static Map<String, Object> responseSchema(String path, String method) {
        Map<String, Object> operation =
                (Map<String, Object>) ((Map<String, Object>) paths().get(path)).get(method);
        Map<String, Object> responses = (Map<String, Object>) operation.get("responses");
        Map<String, Object> ok = (Map<String, Object>) responses.get("200");
        Map<String, Object> content = (Map<String, Object>) ok.get("content");
        Map<String, Object> json = (Map<String, Object>) content.get("application/json");
        return (Map<String, Object>) json.get("schema");
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
            if (method.isAnnotationPresent(PutMapping.class)) {
                found.add("PUT " + base + method.getAnnotation(PutMapping.class).value()[0]);
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
