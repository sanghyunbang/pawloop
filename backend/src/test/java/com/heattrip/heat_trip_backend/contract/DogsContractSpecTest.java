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

import com.heattrip.heat_trip_backend.dog.controller.DogController;
import com.heattrip.heat_trip_backend.dog.dto.DogResponse;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Dogs 계약이 <b>도는 코드</b>와 같은 것을 말하는지 본다 — 이슈 #209.
 *
 * <h2>왜 필요한가</h2>
 * <p>Dogs 는 구현된 도메인인데 계약 스펙 테스트가 없었다. 그 사이 <b>지금 이 순간의 계약
 * 위반</b>이 하나 자랐다 — {@code ageMonths} 가 계약에서 non-null 인데 {@code birth} 없는
 * 반려동물에게 서버가 {@code null} 을 낸다({@code Dogs-medium-3}).
 *
 * <p>고칠 쪽은 계약이다. {@code DogResponse} javadoc 이 이유를 적어 뒀다 — <b>{@code 0} 은
 * "갓 태어났다" 라는 다른 뜻</b>이라 모르는 것을 {@code 0} 으로 눕히면 화면이 "0개월" 을
 * 그리며 거짓말을 한다.
 *
 * <h2>무엇을 재는가</h2>
 * <ul>
 *   <li><b>널 허용</b> — {@code required} 가 아닌 필드는 계약이 {@code "null"} 을 허용해야
 *       한다. {@code DogResponse} 에 {@code @JsonInclude(NON_NULL)} 이 없어 서버가 모든
 *       필드를 <b>항상 실어 보내기</b> 때문이다 — 값이 없으면 키가 사라지는 게 아니라
 *       {@code null} 이 들어간다. 그 전제도 함께 잰다.</li>
 *   <li><b>{@code required}</b> — 거기 있는 필드는 널을 허용하면 안 된다. 허용하면
 *       {@code required} 가 아무것도 보장하지 않는다(ADR-0017 규약 1).</li>
 *   <li><b>남의 것은 404</b> — {@code DogService} 가 소유자 조건을 쿼리 안에 담아 403 을
 *       아예 못 내는데, 계약이 403 을 선언하면 앱이 없는 갈래를 처리한다.</li>
 *   <li><b>코드 ↔ 계약</b> — 매핑 경로와 응답 레코드의 필드.</li>
 * </ul>
 *
 * <p>스프링 컨텍스트를 띄우지 않는다(#21).
 */
class DogsContractSpecTest {

    private static Map<String, Object> spec;

    private static final String DETAIL = "/api/dogs/{dogId}";

    @BeforeAll
    @SuppressWarnings("unchecked")
    static void loadContract() {
        // 파일이 없으면 requireFile 이 여기서 던진다. 못 읽고 통과하면 이 테스트는
        // 아무것도 지키지 않으면서 초록불만 낸다.
        spec = (Map<String, Object>) new Yaml().load(readRepositoryFile("../docs/04-api/openapi.yaml"));
    }

    @Test
    @DisplayName("required 가 아닌 Dog 필드는 계약이 null 을 허용한다 — 서버가 그 필드를 빼지 않는다")
    void optionalFieldsAreNullableInTheContract() {
        // 규칙의 근거: DogResponse 에 @JsonInclude(NON_NULL) 이 없다. 즉 서버는 모든 필드를
        // **항상 실어 보낸다** — 값이 없으면 키가 사라지는 게 아니라 `null` 이 들어간다.
        // 그러면 required 가 아닌 필드는 곧 "null 로 나갈 수 있는 필드" 이고, 계약이 그것을
        // 표현하지 못하면 그 순간부터 서버가 계약 위반이다.
        //
        // 자바 타입으로는 이 판정을 못 한다 — String name 도 참조 타입이지만 항상 채워진다.
        // 그래서 계약 자신의 required 를 기준으로 삼는다.
        assertThat(schemaHasJsonIncludeNonNull())
                .as("DogResponse 에 @JsonInclude(NON_NULL) 이 붙으면 이 규칙의 전제가 무너진다")
                .isFalse();

        List<String> offenders = new ArrayList<>();
        Set<String> required = Set.copyOf(requiredOf("Dog"));
        for (String property : propertyNames("Dog")) {
            if (required.contains(property)) {
                continue;
            }
            List<String> declared = typeOf("Dog", property);
            if (!declared.contains("null")) {
                offenders.add(property + " (required 가 아닌데 계약은 " + declared + ")");
            }
        }

        assertThat(offenders)
                .as("""
                        ageMonths 가 정확히 이 자리에서 났다 — birth 가 nullable 인데 거기서 \
                        파생되는 값이 non-null 이라 스키마 내부가 모순이었고, 서버는 실제로 \
                        null 을 내보내고 있었다 (#209 Dogs-medium-3). breed 도 같은 상태였다.""")
                .isEmpty();
    }

    @Test
    @DisplayName("required 인 Dog 필드는 null 을 허용하지 않는다 — 허용하면 required 가 아무것도 보장하지 않는다")
    void requiredFieldsAreNotNullable() {
        List<String> offenders = new ArrayList<>();
        for (String property : requiredOf("Dog")) {
            if (typeOf("Dog", property).contains("null")) {
                offenders.add(property);
            }
        }

        assertThat(offenders)
                .as("ADR-0017 규약 1 — required 는 '서버가 항상 채우는 필드' 의 최소집합이다")
                .isEmpty();
    }

    @Test
    @DisplayName("남의 반려동물은 403 이 아니라 404 다 — 서버는 403 을 아예 못 낸다")
    void someoneElsesDogIsNotFound() {
        // DogService 가 소유자 조건을 쿼리 안에 담는다. 서비스에 분기가 없으면 그 분기가
        // 응답 코드로 샐 일도 없다 — 403 을 선언하면 앱이 없는 갈래를 처리하게 된다.
        for (String method : List.of("get", "patch", "delete")) {
            assertThat(declaredStatuses(DETAIL, method))
                    .as("""
                            %s %s 가 403 을 선언하면 id 를 훑어 남이 반려동물을 몇 마리 \
                            키우는지 셀 수 있다 (ADR-0017 규약 3).""".formatted(method.toUpperCase(), DETAIL))
                    .doesNotContain("403")
                    .contains("404");
        }
    }

    @Test
    @DisplayName("컨트롤러의 매핑이 전부 계약에 등재돼 있다 — 경로는 코드에서 읽는다")
    void everyImplementedEndpoint_isDeclaredInTheContract() {
        List<String> implemented = operationsOf(DogController.class);

        assertThat(implemented)
                .as("컨트롤러에서 매핑을 하나도 못 읽었다면 이 검사는 아무것도 지키지 않는다")
                .isNotEmpty();
        assertThat(declaredOperations()).containsAll(implemented);
    }

    @Test
    @DisplayName("Dog 스키마의 속성이 DogResponse 의 필드와 정확히 같다")
    void dogSchema_matchesTheResponseRecord() {
        assertThat(propertyNames("Dog"))
                .as("계약과 응답 DTO 가 갈리면 앱이 없는 필드를 읽거나 있는 필드를 모른다")
                .containsExactlyInAnyOrderElementsOf(componentNames(DogResponse.class));
    }

    @Test
    @DisplayName("DogInput 은 ageMonths 를 안 받는다 — 개월 수를 받으면 내일 그 값이 틀린다")
    void inputTakesBirthNotAge() {
        assertThat(propertyNames("DogInput"))
                .as("파생값을 입력으로 받으면 저장하는 순간 낡는다. birth 가 정본이다")
                .doesNotContain("ageMonths")
                .contains("birth");
    }

    // ─────────────────── 도구 ───────────────────

    /** {@code DogResponse} 에 {@code @JsonInclude(NON_NULL)} 이 붙었는지. 규칙의 전제다. */
    private static boolean schemaHasJsonIncludeNonNull() {
        com.fasterxml.jackson.annotation.JsonInclude annotation =
                DogResponse.class.getAnnotation(com.fasterxml.jackson.annotation.JsonInclude.class);
        return annotation != null
                && annotation.value() == com.fasterxml.jackson.annotation.JsonInclude.Include.NON_NULL;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> declaredStatuses(String path, String method) {
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");
        Map<String, Object> operation = (Map<String, Object>) ((Map<String, Object>) paths.get(path)).get(method);
        if (operation == null) {
            throw new AssertionError(path + " 에 " + method + " 오퍼레이션이 없다");
        }
        return ((Map<String, Object>) operation.get("responses")).keySet();
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

    private static List<String> operationsOf(Class<?> controller) {
        String base = controller.isAnnotationPresent(RequestMapping.class)
                ? controller.getAnnotation(RequestMapping.class).value()[0]
                : "";
        List<String> found = new ArrayList<>();
        for (Method method : controller.getDeclaredMethods()) {
            if (method.isAnnotationPresent(GetMapping.class)) {
                found.add("GET " + base + valueOrEmpty(method.getAnnotation(GetMapping.class).value()));
            }
            if (method.isAnnotationPresent(PostMapping.class)) {
                found.add("POST " + base + valueOrEmpty(method.getAnnotation(PostMapping.class).value()));
            }
            if (method.isAnnotationPresent(PatchMapping.class)) {
                found.add("PATCH " + base + valueOrEmpty(method.getAnnotation(PatchMapping.class).value()));
            }
            if (method.isAnnotationPresent(PutMapping.class)) {
                found.add("PUT " + base + valueOrEmpty(method.getAnnotation(PutMapping.class).value()));
            }
            if (method.isAnnotationPresent(DeleteMapping.class)) {
                found.add("DELETE " + base + valueOrEmpty(method.getAnnotation(DeleteMapping.class).value()));
            }
        }
        return found;
    }

    /** {@code @GetMapping} 처럼 경로 없는 매핑은 클래스의 base 가 곧 경로다. */
    private static String valueOrEmpty(String[] value) {
        return value.length == 0 ? "" : value[0];
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schemaOf(String name) {
        Map<String, Object> schemas =
                (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");
        Map<String, Object> schema = (Map<String, Object>) schemas.get(name);
        if (schema == null) {
            throw new AssertionError(name + " 스키마가 계약에 없다");
        }
        return schema;
    }

    @SuppressWarnings("unchecked")
    private static Set<String> propertyNames(String schema) {
        return ((Map<String, Object>) schemaOf(schema).get("properties")).keySet();
    }

    @SuppressWarnings("unchecked")
    private static List<String> requiredOf(String schema) {
        Object required = schemaOf(schema).get("required");
        return required == null ? List.of() : (List<String>) required;
    }

    /**
     * 계약이 그 필드에 허용하는 타입 목록.
     *
     * <p>{@code $ref} 는 <b>널을 허용하지 않는다</b> — 널까지 허용하려면 계약이
     * {@code anyOf: [$ref, {type: "null"}]} 로 적어야 하고, 그 모양이면 아래에서 펼친다.
     *
     * <p>처음엔 {@code type} 이 없을 때 {@code String.valueOf(null)} 이 문자열 {@code "null"}
     * 이 되는 바람에 {@code $ref} 필드가 전부 "널 허용" 으로 읽혔다. 그 상태로는 이 검사가
     * {@code size}·{@code species} 를 위반이라고 잘못 짚는다.
     */
    @SuppressWarnings("unchecked")
    private static List<String> typeOf(String schema, String property) {
        Map<String, Object> props = (Map<String, Object>) schemaOf(schema).get("properties");
        Map<String, Object> field = (Map<String, Object>) props.get(property);
        if (field == null) {
            throw new AssertionError(schema + "." + property + " 이 계약에 없다");
        }

        Object anyOf = field.get("anyOf");
        if (anyOf instanceof List<?> branches) {
            List<String> types = new ArrayList<>();
            for (Object branch : branches) {
                Object type = ((Map<String, Object>) branch).get("type");
                if (type != null) {
                    types.add(String.valueOf(type));
                }
            }
            return types;
        }

        Object type = field.get("type");
        if (type == null) {
            // 순수 $ref — 널을 허용하지 않는다.
            return List.of("$ref");
        }
        return type instanceof List ? (List<String>) type : List.of(String.valueOf(type));
    }

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
