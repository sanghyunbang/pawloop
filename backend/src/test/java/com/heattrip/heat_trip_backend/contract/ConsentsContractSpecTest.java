package com.heattrip.heat_trip_backend.contract;

import java.io.IOException;
import java.lang.reflect.Method;
import java.lang.reflect.RecordComponent;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Arrays;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import com.heattrip.heat_trip_backend.consent.ConsentKind;
import com.heattrip.heat_trip_backend.consent.controller.ConsentController;
import com.heattrip.heat_trip_backend.consent.dto.ConsentEntryRequest;
import com.heattrip.heat_trip_backend.consent.dto.ConsentResponse;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.yaml.snakeyaml.Yaml;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Consents 계약이 <b>도는 코드</b>와 같은 것을 말하는지 본다 — 이슈 #190.
 *
 * <h2>무엇을 재는가</h2>
 * <ul>
 *   <li><b>경로</b> — 계약의 {@code /api/consents} 에 GET·PUT 이 있고 컨트롤러도 그 둘이다.</li>
 *   <li><b>{@code ConsentKind}</b> — 계약의 enum 넷과 서버의 enum 넷이 같은 집합이다.
 *       한쪽에만 값이 생기면 앱이 보낸 것을 서버가 400 으로 거절하거나, 서버가 낸 것을
 *       앱이 못 읽는다.</li>
 *   <li><b>{@code version} 패턴</b> — 계약과 {@code @Pattern} 이 같은 문자열이다. 갈리면
 *       계약이 허용하는 값을 서버가 거절한다.</li>
 *   <li><b>응답 필드</b> — {@code Consent} 스키마의 프로퍼티와 {@code ConsentResponse} 의
 *       컴포넌트가 같다. {@code required} 가 넷 전부다 — 서버가 널을 낼 수 있는 필드가 없다.</li>
 * </ul>
 *
 * <p>스프링 컨텍스트를 띄우지 않는다(#21).
 */
class ConsentsContractSpecTest {

    private static Map<String, Object> spec;

    @BeforeAll
    @SuppressWarnings("unchecked")
    static void loadContract() throws IOException {
        String yaml = Files.readString(
                TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8);
        spec = new Yaml().load(yaml);
    }

    @Test
    @DisplayName("계약의 /api/consents 는 GET·PUT 이고, 컨트롤러도 그 둘뿐이다")
    void pathsMatchTheController() {
        Map<String, Object> path = path("/api/consents");
        assertThat(path.keySet()).containsExactlyInAnyOrder("get", "put");

        assertThat(ConsentController.class.getAnnotation(RequestMapping.class).value())
                .containsExactly("/api/consents");
        Set<String> verbs = new LinkedHashSet<>();
        for (Method m : ConsentController.class.getDeclaredMethods()) {
            if (m.isAnnotationPresent(GetMapping.class)) {
                verbs.add("get");
            }
            if (m.isAnnotationPresent(PutMapping.class)) {
                verbs.add("put");
            }
        }
        assertThat(verbs).containsExactlyInAnyOrder("get", "put");
    }

    @Test
    @DisplayName("ConsentKind 는 계약과 서버가 같은 넷이다")
    @SuppressWarnings("unchecked")
    void consentKindsAgree() {
        List<String> contract = (List<String>) schema("ConsentKind").get("enum");
        Set<String> server = Arrays.stream(ConsentKind.values()).map(Enum::name).collect(Collectors.toSet());

        assertThat(new LinkedHashSet<>(contract))
                .as("한쪽에만 값이 있으면 앱이 보낸 것을 서버가 400 으로 거절하거나 서버가 낸 것을 앱이 못 읽는다")
                .isEqualTo(server);
    }

    @Test
    @DisplayName("version 패턴이 계약과 서버 검증에서 같은 문자열이다")
    @SuppressWarnings("unchecked")
    void versionPatternAgrees() {
        Map<String, Object> input = (Map<String, Object>) properties("ConsentInput").get("version");
        Map<String, Object> output = (Map<String, Object>) properties("Consent").get("version");

        assertThat(input.get("pattern"))
                .as("계약이 허용하는 값을 서버가 거절하면 앱은 원인을 못 본다")
                .isEqualTo(ConsentEntryRequest.VERSION_PATTERN);
        assertThat(output.get("pattern")).isEqualTo(ConsentEntryRequest.VERSION_PATTERN);
    }

    @Test
    @DisplayName("Consent 스키마의 필드가 ConsentResponse 와 같고, 전부 required 다")
    @SuppressWarnings("unchecked")
    void responseFieldsMatch() {
        Set<String> contract = properties("Consent").keySet();
        Set<String> code = Arrays.stream(ConsentResponse.class.getRecordComponents())
                .map(RecordComponent::getName).collect(Collectors.toCollection(LinkedHashSet::new));
        assertThat(contract).isEqualTo(code);

        List<String> required = (List<String>) schema("Consent").get("required");
        assertThat(new LinkedHashSet<>(required))
                .as("서버가 널을 낼 수 있는 필드가 없다 — 레코드 컴포넌트가 전부 원시형이거나 non-null 이다")
                .isEqualTo(contract);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    @SuppressWarnings("unchecked")
    private static Map<String, Object> path(String name) {
        Map<String, Object> paths = (Map<String, Object>) spec.get("paths");
        Map<String, Object> path = (Map<String, Object>) paths.get(name);
        assertThat(path).as("계약에 %s 가 없다", name).isNotNull();
        return path;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> schema(String name) {
        Map<String, Object> components = (Map<String, Object>) spec.get("components");
        Map<String, Object> schemas = (Map<String, Object>) components.get("schemas");
        Map<String, Object> schema = (Map<String, Object>) schemas.get(name);
        assertThat(schema).as("계약에 스키마 %s 가 없다", name).isNotNull();
        return schema;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> properties(String schema) {
        return (Map<String, Object>) schema(schema).get("properties");
    }
}
